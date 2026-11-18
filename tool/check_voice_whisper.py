"""Checks a recorded Egyptian voice with Whisper (speech -> text): every clip is written down by
Whisper and compared with the line it should say; a line is called wrong when many letters differ.
Whisper is not perfect on Egyptian Arabic: --against=yasmine also checks a voice checked by ear,
which shows how much of the error is Whisper's own, and then a line is called wrong only when it is
clearly worse than that voice's.

Whisper only hears the words, not the vowels: a word said with the wrong vowel (nezla / nazla) is
written the same way and is not found here. Those are fixed by ear in tool/voicetut/server.py.

Numbers (all lines together):
  WER        words wrong (changed + missing + extra) / words in the lines; lower is better
  CER        the same for letters (spaces ignored); kinder to small spelling differences
  precision  of the words Whisper heard, how many were right
  recall     of the words the line has, how many Whisper heard
  F1         precision and recall together

Use (Python of tool/.venv, from the project folder):
    tool\\.venv\\Scripts\\python tool/check_voice_whisper.py                    # check VoiceTut Clone
    tool\\.venv\\Scripts\\python tool/check_voice_whisper.py --fix              # + make the wrong lines again
    tool\\.venv\\Scripts\\python tool/check_voice_whisper.py yasmine           # check another voice
--fix (VoiceTut Clone only) tries other takes (seeds) of each wrong line and keeps the one Whisper
understands best. Build the app again afterwards. Results: tool/try/whisper/<voice>.tsv
"""

import hashlib
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "voicetut"))

import make_egyptian_voice_voicetut_clone as clone  # noqa: E402

OUT = os.path.join(HERE, "try", "whisper")
WHISPER = "large-v3"
# wrong: letters wrong (CER) above BAD and above the ear-checked voice's CER on the line + MARGIN
BAD, MARGIN = 0.2, 0.1

# ----------------------------------------------------------------- text -> comparable text

ENGLISH = {"romanian deadlift": "رومانيان ديدليفت", "sumo deadlift": "سومو ديدليفت",
           "biceps curl": "بايسبس كيرل", "bench press": "بنش بريس", "deadlift": "ديدليفت",
           "squat": "سكوات"}
TASHKEEL = re.compile(r"[ً-ْٰـ]")  # + tatweel
LETTERS = str.maketrans({"أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ى": "ي", "ة": "ه", "ؤ": "و",
                         "ئ": "ي", "ء": "ق",  # Egyptian ء is written for ق (ءول = قول)
                         "ث": "ت", "ذ": "د", "ظ": "ض"})  # Whisper writes standard Arabic letters


def number_words():
    """'23' -> the app's words (تلاتة وعشرين)"""
    from server import TEENS, TENS, UNITS
    units, teens, tens = list(UNITS), list(TEENS), list(TENS)
    words = {str(i + 1): w for i, w in enumerate(units)}
    words.update({str(i + 10): w for i, w in enumerate(teens)})
    for i, w in enumerate(tens[:-1]):
        t = (i + 2) * 10
        words[str(t)] = w
        for u in range(1, 10):
            words[str(t + u)] = f"{units[u - 1]} و{w}"
    words["100"] = tens[-1]
    return words


NUMBERS = None


def plain(text):
    global NUMBERS
    if NUMBERS is None:
        NUMBERS = number_words()
    t = text.lower()
    t = t.translate(str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789"))
    for en, ar in ENGLISH.items():
        t = t.replace(en, ar)
    t = re.sub(r"\d+", lambda m: NUMBERS.get(m.group(), m.group()), t)
    t = re.sub(r"ء(?![ء-ي])", "", TASHKEEL.sub("", t))  # ء at the end of a word (هدوء = هدو)
    t = t.translate(LETTERS)
    t = re.sub(r"[^\w\s]|_", " ", t)
    return " ".join(t.split())


def score(said, heard):
    """dict with the counts of one line"""
    import jiwer
    ref, hyp = plain(said), plain(heard)
    if not hyp:
        n = len(ref.split())
        return {"hits": 0, "sub": 0, "del": n, "ins": 0, "words": n, "cer": 1.0}
    w = jiwer.process_words(ref, hyp)
    cer = jiwer.cer(ref.replace(" ", ""), hyp.replace(" ", ""))
    return {"hits": w.hits, "sub": w.substitutions, "del": w.deletions, "ins": w.insertions,
            "words": len(ref.split()), "cer": min(cer, 1.0)}


def totals(scores, letters):
    h = sum(s["hits"] for s in scores)
    s_ = sum(s["sub"] for s in scores)
    d = sum(s["del"] for s in scores)
    i = sum(s["ins"] for s in scores)
    n = sum(s["words"] for s in scores)
    p = h / max(h + s_ + i, 1)
    r = h / max(h + s_ + d, 1)
    cer = sum(s["cer"] * c for s, c in zip(scores, letters)) / max(sum(letters), 1)
    return {"WER": (s_ + d + i) / max(n, 1), "CER": cer, "precision": p, "recall": r,
            "F1": 2 * p * r / max(p + r, 1e-9),
            "lines all right": sum(s["sub"] + s["del"] + s["ins"] == 0 for s in scores) / len(scores)}


# ----------------------------------------------------------------- Whisper

_whisper = None


def hear(path):
    global _whisper
    if _whisper is None:
        from faster_whisper import WhisperModel
        _whisper = WhisperModel(WHISPER, device="cpu", compute_type="int8", cpu_threads=os.cpu_count())
    segs, _ = _whisper.transcribe(load_16k(path), language="ar", beam_size=5, temperature=0,
                                  condition_on_previous_text=False, vad_filter=False)
    return " ".join(s.text.strip() for s in segs).strip()


def load_16k(path):
    """the clip as 16 kHz mono floats (faster-whisper's own reader needs an older PyAV)"""
    from math import gcd

    import numpy as np
    import soundfile as sf
    from scipy.signal import resample_poly
    data, rate = sf.read(path, dtype="float32", always_2d=True)
    data = data.mean(axis=1)
    g = gcd(16000, rate)
    return resample_poly(data, 16000 // g, rate // g).astype(np.float32)


def md5(path):
    with open(path, "rb") as f:
        return hashlib.md5(f.read()).hexdigest()


class Heard:
    """Whisper's text of each clip, kept in tool/try/whisper/heard.json (by the clip's bytes)"""

    def __init__(self):
        self.path = os.path.join(OUT, "heard.json")
        self.data = clone.load_json(self.path)

    def __call__(self, mp3_path):
        h = md5(mp3_path)
        if h not in self.data:
            self.data[h] = hear(mp3_path)
            if len(self.data) % 10 == 0:
                self.save()
        return self.data[h]

    def save(self):
        os.makedirs(OUT, exist_ok=True)
        clone.save_json(self.path, self.data)


# ----------------------------------------------------------------- check / fix

def said_by(folder, pieces):
    """what each clip of the voice should say"""
    if folder == clone.FOLDER:
        return {k: clone.spoken(t) for k, t in pieces.items()}
    import make_egyptian_voice_elevenlabs_voices as eleven
    if folder in eleven.VOICES:
        return {k: eleven.spoken(t, folder) for k, t in pieces.items()}
    return dict(pieces)


def check(folder, pieces, heard, quiet=False):
    """key -> (said, heard, score) for the clips of `folder`"""
    said = said_by(folder, pieces)
    out = {}
    keys = [k for k in pieces if os.path.exists(os.path.join(clone.ASSET_DIR, folder, k + ".mp3"))]
    for n, k in enumerate(keys, 1):
        h = heard(os.path.join(clone.ASSET_DIR, folder, k + ".mp3"))
        out[k] = (said[k], h, score(said[k], h))
        if not quiet and n % 25 == 0:
            print(f"  {folder}: {n}/{len(keys)} heard", flush=True)
    heard.save()
    return out


def report(name, result):
    keys = list(result)
    t = totals([result[k][2] for k in keys], [len(plain(result[k][0]).replace(" ", "")) for k in keys])
    print(f"{name} ({len(keys)} lines): " + "   ".join(
        f"{k} {v * 100:.1f}%" for k, v in t.items()))
    return t


def wrong(result, base):
    """keys of the lines clearly worse than the ear-checked voice"""
    out = []
    for k, (_, _, s) in result.items():
        b = base[k][2]["cer"] if base and k in base else 0.0
        if s["cer"] > BAD and s["cer"] > b + MARGIN:
            out.append(k)
    return out


def write_tsv(folder, result, base, bad):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, folder + ".tsv")
    with open(path, "w", encoding="utf-8") as f:
        f.write("key\twrong\tCER\tCER ear-checked voice\tsaid\theard\n")
        for k in sorted(result, key=lambda k: -result[k][2]["cer"]):
            said, h, s = result[k]
            b = f"{base[k][2]['cer']:.2f}" if base and k in base else ""
            f.write(f"{k}\t{'yes' if k in bad else ''}\t{s['cer']:.2f}\t{b}\t{said}\t{h}\n")
    return path


def fix(keys, result, base, heard, takes):
    """make each line again with takes 1..takes, keep the one Whisper understands best"""
    recorded = clone.load_json(clone.RECORDED)
    seeds = recorded.setdefault(clone.FOLDER + "_seed", {})
    ref, ref_text = clone.reference()
    tts = clone.load_model()
    tmp = tempfile.mkdtemp()
    wav = os.path.join(tmp, "line.wav")
    for n, k in enumerate(keys, 1):
        said, _, s = result[k]
        target = (base[k][2]["cer"] if base and k in base else 0.0) + 0.02
        best_seed, best = seeds.get(k, 0), s["cer"]
        best_mp3 = None
        for seed in range(1, takes + 1):
            if seed == seeds.get(k, 0):
                continue
            mp3_path = os.path.join(tmp, f"{k}_{seed}.mp3")
            clone.make(tts, said, ref, ref_text, seed, wav, mp3_path)
            c = score(said, heard(mp3_path))["cer"]
            if c < best:
                best_seed, best, best_mp3 = seed, c, mp3_path
            if best <= target:
                break
        if best_mp3:
            os.replace(best_mp3, os.path.join(clone.ASSET_DIR, clone.FOLDER, k + ".mp3"))
            seeds[k] = best_seed
            clone.save_json(clone.RECORDED, recorded)
        print(f"  {n}/{len(keys)} {k}: CER {s['cer']:.2f} -> {best:.2f}"
              f"{f' (take {best_seed})' if best_mp3 else ' (kept)'}", flush=True)
    heard.save()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "") for a in sys.argv[1:] if a.startswith("--"))
    folder = args[0] if args else clone.FOLDER
    against = opts.get("against", "")
    takes = int(opts.get("takes", "6"))
    pieces = clone.load_pieces()
    heard = Heard()

    base = check(against, pieces, heard) if against else None
    if base:
        report(f"{against} (checked by ear: Whisper's own error)", base)
    result = check(folder, pieces, heard)
    report(folder, result)
    bad = wrong(result, base)
    print(f"{len(bad)} lines wrong; list: {write_tsv(folder, result, base, bad)}")

    if "fix" in opts and bad:
        if folder != clone.FOLDER:
            sys.exit("--fix only makes VoiceTut Clone lines")
        fix(bad, result, base, heard, takes)
        result = check(folder, pieces, heard, quiet=True)
        report(folder + " after the fix", result)
        bad = wrong(result, base)
        print(f"{len(bad)} lines still wrong; list: {write_tsv(folder, result, base, bad)}")


if __name__ == "__main__":
    main()
