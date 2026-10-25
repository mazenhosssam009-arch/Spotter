"""Records the Egyptian Arabic voice clips of the voice coach with the free Microsoft Edge
"Read aloud" voices (ar-EG-ShakirNeural = male, ar-EG-SalmaNeural = female).
No account, no card. Unofficial: Edge's read-aloud service is not an official API.

Run from the project folder (where pubspec.yaml is):
    dart run tool/make_egyptian_voice.dart --list      (writes assets/voice/ar_eg/pieces.txt)
    python -m pip install edge-tts                      (once)
    python tool/make_egyptian_voice_edge.py

Run both again after changing Arabic text in phrase_bank.dart: only new pieces are made,
and clips nobody uses any more are deleted.

Pronunciation: if the voice says a word wrong, add a line to tool/pronunciation.txt
(word = how to say it, e.g. with tashkeel) and run the script again. Only the clips with
that word are recorded again; the app does not change.

Judge the whole voice: record ~30 real coach lines WITH and WITHOUT tashkeel
(tool/try/tashkeel/ and tool/try/plain/, same numbers = same line, list in tool/try/list.txt):
    python tool/make_egyptian_voice_edge.py --sample
Record everything without tashkeel (if plain sounded better):
    python tool/make_egyptian_voice_edge.py --no-tashkeel

Try spellings by ear before changing the file (writes tool/try/1.mp3, 2.mp3, ...):
    python tool/make_egyptian_voice_edge.py --try "شوية" "شُوَيَّة" "شويّا"
    python tool/make_egyptian_voice_edge.py --try --female "سبعتاشر" "سَبَعْتاشَر"
"""

import asyncio
import json
import os
import re
import sys

try:
    import edge_tts
except ImportError:
    print("edge-tts is not installed. Run:  python -m pip install edge-tts")
    sys.exit(1)

ASSET_DIR = os.path.join("assets", "voice", "ar_eg")
PIECES = os.path.join(ASSET_DIR, "pieces.txt")
RECORDED = os.path.join(ASSET_DIR, "recorded.json")  # which spoken text each clip has
PRONUNCIATION = os.path.join("tool", "pronunciation.txt")
# letters and tashkeel (not punctuation like "،"), so "شوية،" still matches "شوية"
ARABIC_LETTER = r"[\w\u064B-\u0652\u0670\u0640]"
VOICES = {"male": "ar-EG-ShakirNeural", "female": "ar-EG-SalmaNeural"}
# Egyptians say a final ة as "a": write it as ا so the voice does not swallow it
FINAL_TAA_AS_ALEF = True
# False = remove all tashkeel before recording (or pass --no-tashkeel)
TASHKEEL = "--no-tashkeel" not in sys.argv
TASHKEEL_MARKS = r"[\u064B-\u0652\u0670]"
PARALLEL = 4  # recordings at the same time
RETRIES = 5


def load_pieces():
    if not os.path.exists("pubspec.yaml"):
        print("Run this from your project folder (the one with pubspec.yaml).")
        sys.exit(1)
    if not os.path.exists(PIECES):
        print("pieces.txt is missing. First run:  dart run tool/make_egyptian_voice.dart --list")
        sys.exit(1)
    pieces = {}
    with open(PIECES, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if "\t" not in line:
                continue
            key, text = line.split("\t", 1)
            if key and text.strip():
                pieces[key] = text
    return pieces


def load_pronunciation():
    """lines "word = spoken" (# = comment). Longer words are replaced first."""
    rules = []
    if os.path.exists(PRONUNCIATION):
        with open(PRONUNCIATION, encoding="utf-8") as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if "=" not in line:
                    continue
                word, spoken = (x.strip() for x in line.split("=", 1))
                if word and spoken:
                    rules.append((word, spoken))
    rules.sort(key=lambda r: -len(r[0]))
    # also matches with و / ل / ب in front ("وعشرين", "لبرّه" stays as written)
    return [(re.compile(r"(?<!%s)(و|ل|ب)?%s(?!%s)" % (ARABIC_LETTER, re.escape(w), ARABIC_LETTER)), sp)
            for w, sp in rules]


def spoken(text, rules):
    for pattern, sp in rules:
        text = pattern.sub(lambda m, sp=sp: (m.group(1) or "") + sp, text)
    if FINAL_TAA_AS_ALEF:
        text = re.sub(r"ة(?!%s)" % ARABIC_LETTER, "ا", text)
    if not TASHKEEL:
        text = re.sub(TASHKEEL_MARKS, "", text)
    return text


async def record(voice, text, path):
    """one clip; True when the file was written"""
    for attempt in range(1, RETRIES + 1):
        try:
            tmp = path + ".part"
            await edge_tts.Communicate(text, voice).save(tmp)
            if os.path.getsize(tmp) > 0:
                os.replace(tmp, path)
                return True
        except Exception as e:  # network hiccup / too many requests: wait and retry
            if attempt == RETRIES:
                print(f"\n  failed {os.path.basename(path)}: {e}")
            await asyncio.sleep(2 * attempt)
    return False


async def make_voice(folder, voice, pieces, rules, recorded):
    out_dir = os.path.join(ASSET_DIR, folder)
    os.makedirs(out_dir, exist_ok=True)
    before = recorded.setdefault(folder, {})

    def ok_already(k, t):
        f = os.path.join(out_dir, k + ".mp3")
        # recorded before this pronunciation file existed = recorded from the plain text
        return (os.path.exists(f) and os.path.getsize(f) > 0
                and before.get(k, t) == spoken(t, rules))

    todo = [(k, spoken(t, rules)) for k, t in pieces.items() if not ok_already(k, t)]
    total, done, failed = len(todo), 0, 0
    sem = asyncio.Semaphore(PARALLEL)

    async def one(key, text):
        nonlocal done, failed
        async with sem:
            ok = await record(voice, text, os.path.join(out_dir, key + ".mp3"))
            done += 1
            if ok:
                before[key] = text
            else:
                failed += 1
            print(f"\r{folder}: {done}/{total}   ", end="", flush=True)

    await asyncio.gather(*(one(k, t) for k, t in todo))
    print(f"\r{folder}: {total - failed} recorded, {len(pieces) - total} unchanged, {failed} failed")

    # clips of old text that is not used any more
    for name in os.listdir(out_dir):
        if name.endswith(".mp3") and name[:-4] not in pieces:
            os.remove(os.path.join(out_dir, name))
        if name.endswith(".part"):
            os.remove(os.path.join(out_dir, name))

    return sorted(k for k in pieces
                  if os.path.exists(os.path.join(out_dir, k + ".mp3")))


async def try_spellings(args):
    voice = VOICES["female" if "--female" in args else "male"]
    words = [a for a in args if not a.startswith("--")]
    out = os.path.join("tool", "try")
    os.makedirs(out, exist_ok=True)
    for name in os.listdir(out):
        os.remove(os.path.join(out, name))
    for i, w in enumerate(words, 1):
        await record(voice, w, os.path.join(out, f"{i}.mp3"))
    print(f"{len(words)} files in tool/try/ (1.mp3 = the first spelling, ...). Listen and pick one.")


async def sample(args):
    global TASHKEEL
    path = os.path.join("tool", "sample.txt")
    if not os.path.exists(path):
        print("sample.txt is missing. First run:  dart run tool/make_egyptian_voice.dart --list")
        sys.exit(1)
    with open(path, encoding="utf-8") as f:
        lines = [l.strip() for l in f if l.strip()]
    voice = VOICES["female" if "--female" in args else "male"]
    rules = load_pronunciation()
    base = os.path.join("tool", "try")
    for mode in ("tashkeel", "plain"):
        out = os.path.join(base, mode)
        os.makedirs(out, exist_ok=True)
        for name in os.listdir(out):
            os.remove(os.path.join(out, name))
        TASHKEEL = mode == "tashkeel"
        jobs = [record(voice, spoken(t, rules), os.path.join(out, f"{i:02d}.mp3"))
                for i, t in enumerate(lines, 1)]
        await asyncio.gather(*jobs)
        print(f"{mode}: {len(lines)} files")
    with open(os.path.join(base, "list.txt"), "w", encoding="utf-8") as f:
        for i, t in enumerate(lines, 1):
            f.write(f"{i:02d}  {t}\n")
    print("Compare tool/try/tashkeel/ with tool/try/plain/ (list.txt says what each number is).")


async def main():
    if "--sample" in sys.argv:
        await sample(sys.argv[1:])
        return
    if "--try" in sys.argv:
        await try_spellings(sys.argv[1:])
        return
    pieces = load_pieces()
    rules = load_pronunciation()
    recorded = {}
    if os.path.exists(RECORDED):
        with open(RECORDED, encoding="utf-8") as f:
            recorded = json.load(f)
    print(f"{len(pieces)} Arabic pieces x 2 voices, {len(rules)} pronunciation fixes")
    manifest = {}
    for folder, voice in VOICES.items():
        manifest[folder] = await make_voice(folder, voice, pieces, rules, recorded)
        recorded[folder] = {k: v for k, v in recorded[folder].items() if k in pieces}
        with open(RECORDED, "w", encoding="utf-8") as f:
            json.dump(recorded, f, ensure_ascii=False, indent=1)
    with open(os.path.join(ASSET_DIR, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    print("Done. Clips are in assets/voice/ar_eg/")


if __name__ == "__main__":
    asyncio.run(main())
