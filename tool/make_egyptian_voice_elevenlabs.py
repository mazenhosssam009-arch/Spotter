"""Records the Egyptian Arabic voice clips of the voice coach with ElevenLabs (Eleven v4),
which sounds much more like a real person than the Microsoft voices.
The app does not change: the clips go to the same place (assets/voice/ar_eg/male, female)
with the same file names, and the app plays them as before.

You need an ElevenLabs account and API key (elevenlabs.io > Developers > API keys).
Never put the key in the code or on GitHub: give it to the script in the terminal only.

Run from the project folder (where pubspec.yaml is). PowerShell:
    $env:ELEVENLABS_API_KEY = "your key"
Git Bash:
    export ELEVENLABS_API_KEY="your key"

1) Find Egyptian voices (prints name, gender, voice id and a preview link to listen to):
    python tool/make_egyptian_voice_elevenlabs.py --find
   If a voice you like is in the Voice Library, click "Add to my voices" on elevenlabs.io
   first, so the API may use it.

2) Hear real coach lines with a few voices before recording everything
   (writes tool/try/elevenlabs/<voice>/01.mp3 ...; list.txt says what each number is):
    python tool/make_egyptian_voice_elevenlabs.py --sample VOICE_ID VOICE_ID VOICE_ID
   Add --no-tashkeel to hear the same lines without tashkeel.

3) Record every piece the app says, with the voices you picked:
    dart run tool/make_egyptian_voice.dart --list
    python tool/make_egyptian_voice_elevenlabs.py --male VOICE_ID --female VOICE_ID
   Add --no-tashkeel if the samples sounded better without it.
   Run it again after changing Arabic text in phrase_bank.dart: only new or changed pieces
   are recorded (that saves characters), and clips nobody uses any more are deleted.

Each run prints how many characters it will use, before it starts.
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

try:  # use the Windows / macOS certificate store (Python's own one fails on some PCs)
    import truststore

    truststore.inject_into_ssl()
except ImportError:
    pass

API = "https://api.elevenlabs.io"
MODEL = "eleven_v4"
LANGUAGE = "ar"
# 64 kbps is plenty for short spoken cues and keeps the app small
OUTPUT_FORMAT = "mp3_44100_64"

ASSET_DIR = os.path.join("assets", "voice", "ar_eg")
PIECES = os.path.join(ASSET_DIR, "pieces.txt")
# which text + voice each clip was recorded with (so a re-run only records what changed)
RECORDED = os.path.join(ASSET_DIR, "recorded_elevenlabs.json")
SAMPLE_DIR = os.path.join("tool", "try", "elevenlabs")
TASHKEEL_MARKS = r"[ً-ْٰ]"
RETRIES = 6

# real coach lines (the app's own wording) for --sample
SAMPLE_LINES = [
    "اِرْفَع صِدْرَك",
    "مَتِخَلّيش رُكْبِتَك تِدْخُل لِجُوَّه",
    "تَلاتَة ريبْس",
    "اِرْجَع لِوَرا شُوَيَّة، عايِز أَشوفَك مِن راسَك لِرِجْلَك",
    "الراحَة خِلْصِت، جاهِز لِلسِّت اللي جاي؟",
    "فاضِل اِتْنَيْن! يَلّا!",
    "دي مَتْحَسَبِتْش، اِنْزِل أَكْتَر",
    "عاش! كَمِّل كِدَه!",
]


def key():
    k = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not k:
        print("Set your key first (it is never saved):\n"
              '  PowerShell:  $env:ELEVENLABS_API_KEY = "your key"\n'
              '  Git Bash:    export ELEVENLABS_API_KEY="your key"')
        sys.exit(1)
    return k


def arg(name):
    if name in sys.argv:
        i = sys.argv.index(name)
        if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith("--"):
            return sys.argv[i + 1]
    return None


def spoken(text):
    if "--no-tashkeel" in sys.argv:
        return re.sub(TASHKEEL_MARKS, "", text)
    return text


def request(method, path, body=None, query=None):
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("xi-api-key", key())
    if data is not None:
        req.add_header("Content-Type", "application/json")
    return urllib.request.urlopen(req, timeout=60)


def tts(voice_id, text):
    """mp3 bytes of [text] in [voice_id], or None"""
    body = {"text": text, "model_id": MODEL, "language_code": LANGUAGE}
    for attempt in range(1, RETRIES + 1):
        try:
            with request("POST", f"/v1/text-to-speech/{voice_id}", body, {"output_format": OUTPUT_FORMAT}) as r:
                audio = r.read()
                if audio:
                    return audio
        except urllib.error.HTTPError as e:
            msg = e.read().decode("utf-8", "replace")
            if e.code in (401, 403):
                print(f"\nElevenLabs refused the key ({e.code}): {msg}")
                sys.exit(1)
            if e.code == 404 or "voice_not_found" in msg:
                print(f"\nVoice {voice_id} not found. Add it to 'My voices' on elevenlabs.io first.")
                sys.exit(1)
            if "quota" in msg.lower():
                print(f"\nOut of characters on this ElevenLabs plan: {msg}")
                sys.exit(1)
            if e.code == 400 and "language_code" in msg and "language_code" in body:
                body.pop("language_code")  # this model works the language out itself
                continue
            if e.code == 402 or "paid" in msg.lower() or "subscription" in msg.lower():
                print(f"\nElevenLabs needs a paid plan for this ({e.code}): {msg}")
                sys.exit(1)
            if e.code == 400 or e.code == 422:
                print(f"\nElevenLabs did not accept the request ({e.code}): {msg}")
                return None
            # 429 = too many at once / too fast: wait and try again
            wait = min(30, 3 * attempt)
            print(f"\n  [ElevenLabs {e.code}, retry {attempt}/{RETRIES} in {wait}s]: {msg[:300]}", flush=True)
            time.sleep(wait)
        except (urllib.error.URLError, TimeoutError) as e:
            print(f" [network: {e}, retry]", end="")
            time.sleep(3 * attempt)
    return None


def find():
    """Egyptian-accented Arabic voices: your own ones and the public Voice Library"""
    found = []
    try:
        with request("GET", "/v2/voices", query={"page_size": 100}) as r:
            for v in json.load(r).get("voices", []):
                found.append(("mine", v))
    except urllib.error.HTTPError as e:
        print("could not read your voices:", e.code, e.read().decode("utf-8", "replace"))
    for page in range(5):
        try:
            with request("GET", "/v1/shared-voices",
                         query={"language": "ar", "page_size": 100, "page": page}) as r:
                data = json.load(r)
        except urllib.error.HTTPError as e:
            print("could not read the Voice Library:", e.code, e.read().decode("utf-8", "replace"))
            break
        for v in data.get("voices", []):
            found.append(("library", v))
        if not data.get("has_more"):
            break

    def egyptian(v):
        blob = json.dumps(v, ensure_ascii=False).lower()
        return "egypt" in blob or "مصر" in blob or "مصري" in blob

    rows = [(where, v) for where, v in found if egyptian(v)]
    if not rows:
        print("No Egyptian voices found. Search 'Egyptian' in the Voice Library on elevenlabs.io.")
        return
    print(f"{len(rows)} Egyptian voices (listen to the preview link, copy the voice id):\n")
    for where, v in rows:
        labels = v.get("labels") or {}
        gender = v.get("gender") or labels.get("gender") or "?"
        preview = v.get("preview_url") or ""
        print(f"[{where}] {v.get('name', '?')}  ({gender})\n    voice id: {v.get('voice_id')}\n    preview:  {preview}\n")
    print("Library voices: click 'Add to my voices' on elevenlabs.io before using them here.")


def sample(voice_ids):
    if not voice_ids:
        print("Give one or more voice ids:  --sample VOICE_ID VOICE_ID")
        sys.exit(1)
    chars = sum(len(spoken(l)) for l in SAMPLE_LINES) * len(voice_ids)
    print(f"{len(SAMPLE_LINES)} lines x {len(voice_ids)} voices = about {chars} characters")
    tag = "plain" if "--no-tashkeel" in sys.argv else "tashkeel"
    for vid in voice_ids:
        out = os.path.join(SAMPLE_DIR, f"{vid}_{tag}")
        os.makedirs(out, exist_ok=True)
        for i, line in enumerate(SAMPLE_LINES, 1):
            audio = tts(vid, spoken(line))
            if audio:
                with open(os.path.join(out, f"{i:02d}.mp3"), "wb") as f:
                    f.write(audio)
        print(f"  {out}")
    with open(os.path.join(SAMPLE_DIR, "list.txt"), "w", encoding="utf-8") as f:
        for i, line in enumerate(SAMPLE_LINES, 1):
            f.write(f"{i:02d}  {line}\n")
    print(f"Listen in {SAMPLE_DIR}/ (list.txt says what each number is).")


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
            if "\t" in line:
                k, t = line.split("\t", 1)
                if k and t.strip():
                    pieces[k] = t
    return pieces


def record_all(voices):
    pieces = load_pieces()
    recorded = {}
    if os.path.exists(RECORDED):
        with open(RECORDED, encoding="utf-8") as f:
            recorded = json.load(f)

    def todo_for(folder, vid):
        before = recorded.get(folder, {})
        out_dir = os.path.join(ASSET_DIR, folder)
        return [(k, spoken(t)) for k, t in pieces.items()
                if before.get(k) != f"{vid}|{spoken(t)}"
                or not os.path.exists(os.path.join(out_dir, k + ".mp3"))]

    plan = {folder: todo_for(folder, vid) for folder, vid in voices.items()}
    chars = sum(len(t) for todo in plan.values() for _, t in todo)
    print(f"{len(pieces)} pieces; to record: "
          + ", ".join(f"{folder} {len(todo)}" for folder, todo in plan.items())
          + f"  = about {chars} characters")
    if chars and "--yes" not in sys.argv:
        if input("Go on? [y/N] ").strip().lower() != "y":
            return

    manifest = {}
    for folder, vid in voices.items():
        out_dir = os.path.join(ASSET_DIR, folder)
        os.makedirs(out_dir, exist_ok=True)
        done = recorded.setdefault(folder, {})
        todo = plan[folder]
        failed = 0
        for i, (k, text) in enumerate(todo, 1):
            print(f"\r{folder}: {i}/{len(todo)}   ", end="", flush=True)
            audio = tts(vid, text)
            if not audio:
                failed += 1
                continue
            with open(os.path.join(out_dir, k + ".mp3"), "wb") as f:
                f.write(audio)
            done[k] = f"{vid}|{text}"
            # saved after every clip: a stopped run continues where it was
            with open(RECORDED, "w", encoding="utf-8") as f:
                json.dump(recorded, f, ensure_ascii=False, indent=1)
        print(f"\r{folder}: {len(todo) - failed} recorded, {len(pieces) - len(todo)} unchanged, {failed} failed")
        # clips of text nobody uses any more
        for name in os.listdir(out_dir):
            if name.endswith(".mp3") and name[:-4] not in pieces:
                os.remove(os.path.join(out_dir, name))
        recorded[folder] = {k: v for k, v in done.items() if k in pieces}
        manifest[folder] = sorted(k for k in pieces if os.path.exists(os.path.join(out_dir, k + ".mp3")))

    with open(RECORDED, "w", encoding="utf-8") as f:
        json.dump(recorded, f, ensure_ascii=False, indent=1)
    # a voice not given this time keeps its clips in the manifest
    path = os.path.join(ASSET_DIR, "manifest.json")
    old = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            old = json.load(f)
    old.update(manifest)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(old, f, indent=1)
    print("Done. Clips are in assets/voice/ar_eg/. Build the app again to hear them.")


def main():
    if "--find" in sys.argv:
        find()
    elif "--sample" in sys.argv:
        i = sys.argv.index("--sample")
        sample([a for a in sys.argv[i + 1:] if not a.startswith("--")])
    else:
        voices = {f: v for f, v in (("male", arg("--male")), ("female", arg("--female"))) if v}
        if not voices:
            print(__doc__)
            sys.exit(1)
        record_all(voices)


if __name__ == "__main__":
    main()
