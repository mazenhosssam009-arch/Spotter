"""The Egyptian Arabic voices of the voice coach, recorded once with Google's Gemini
text-to-speech and bundled in the app (works offline). Six voices: Puck and Zephyr are the
defaults (male / female), Fenrir, Orus, Kore and Leda can be picked in the voice settings.

Key: Google AI Studio (aistudio.google.com) > Get API key. It is only given in the
terminal and never saved. Never put it in the code or on GitHub.

Run from the project folder (where pubspec.yaml is). PowerShell:
    $env:GEMINI_API_KEY = "your key"

Record the clips (Puck and Zephyr first, then the others):
    dart run tool/make_egyptian_voice.dart --list
    python tool/make_egyptian_voice_gemini.py --record
    python tool/make_egyptian_voice_gemini.py --record puck zephyr      (only these voices)

- Several lines are recorded in one request and cut at the pauses, then Gemini listens to
  every clip and checks it says its line. A batch that fails is recorded again in halves.
- The free plan allows few requests a day. When Google says the daily limit is reached the
  script stops: run the SAME command the next day and it continues where it stopped.
- A voice appears in the app only when all its clips are recorded (manifest.json).
- After changing Arabic text in phrase_bank.dart, run both commands again: only new or
  changed lines are recorded.

Samples to judge by ear (tool/try/gemini/<voice>_<gender>.wav, 8 coach lines each):
    python tool/make_egyptian_voice_gemini.py --sample [--voices Puck Zephyr]
Models this key can use:
    python tool/make_egyptian_voice_gemini.py --models
"""

import base64
import difflib
import json
import os
import re
import struct
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_split  # noqa: E402

try:  # use the Windows / macOS certificate store (Python's own one fails on some PCs)
    import truststore

    truststore.inject_into_ssl()
except ImportError:
    pass

API = "https://generativelanguage.googleapis.com/v1beta"
# newest first; the first one this key can use is taken
TTS_MODELS = ["gemini-3.8-flash-tts", "gemini-2.5-flash-preview-tts"]
# listens to the clips to check them
CHECK_MODELS = ["gemini-3.8-flash", "gemini-3-flash", "gemini-2.5-flash", "gemini-2.0-flash"]

# clip folder -> (Gemini voice, gender). Order = recording order (defaults first).
VOICES = {
    "puck": ("Puck", "male"),
    "zephyr": ("Zephyr", "female"),
    "fenrir": ("Fenrir", "male"),
    "orus": ("Orus", "male"),
    "kore": ("Kore", "female"),
    "leda": ("Leda", "female"),
}

ASSET_DIR = os.path.join("assets", "voice", "ar_eg")
PIECES = os.path.join(ASSET_DIR, "pieces.txt")
MANIFEST = os.path.join(ASSET_DIR, "manifest.json")
RECORDED = os.path.join(ASSET_DIR, "recorded_gemini.json")
SAMPLE_DIR = os.path.join("tool", "try", "gemini")
BATCH = 20  # lines per request (fewer requests = fits the free daily limit)
MP3_KBPS = 48

# The instruction and the words to say are clearly separated: with one long instruction
# sentence a voice read part of it out loud.
DIRECTION = """### DIRECTOR'S NOTES
Voice: an energetic Egyptian gym coach from Cairo talking to a client.
Accent: natural, casual Egyptian Arabic (masri), everyday Egyptian pronunciation, not formal Arabic.
Pace: clear and lively. Pause for about one second after every line.
Speak ONLY the lines under TRANSCRIPT, in order, and nothing else.

### TRANSCRIPT
"""

# the app's own coach lines, written the way Egyptians type them (no tashkeel)
SAMPLE_LINES = [
    "ارفع صدرك",
    "متخليش ركبتك تدخل لجوه",
    "تلاتة ريبس",
    "ارجع لورا شوية، عايز اشوفك من راسك لرجلك",
    "الراحة خلصت، جاهز للسِت اللي جاي؟",
    "فاضل اتنين! يلا!",
    "دي متحسبتش، انزل اكتر",
    "عاش! كمل كده!",
]

TASHKEEL = re.compile(r"[ً-ْٰ]")


class DailyLimit(Exception):
    """Google's free daily limit is used up"""


# ------------------------------------------------------------------ Google API


def key():
    k = os.environ.get("GEMINI_API_KEY", "").strip()
    if not k:
        print("Set your key first (it is never saved):\n"
              '  PowerShell:  $env:GEMINI_API_KEY = "your key"\n'
              '  Git Bash:    export GEMINI_API_KEY="your key"')
        sys.exit(1)
    return k


def call(method, path, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("x-goog-api-key", key())
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.load(r)


def _limit_info(msg):
    """the useful part of Google's quota error: which daily limit and how many requests it allows"""
    ids = re.findall(r'"quotaId":\s*"([^"]+)"', msg)
    vals = re.findall(r'"quotaValue":\s*"?(\d+)', msg)
    day = [f"{q} = {v} requests" for q, v in zip(ids, vals) if "Day" in q]
    return "; ".join(day) or msg[:300]


def generate(model, body):
    """generateContent with waiting on the per-minute limit; raises DailyLimit"""
    for attempt in range(1, 9):
        try:
            return call("POST", f"/models/{model}:generateContent", body)
        except urllib.error.HTTPError as e:
            msg = e.read().decode("utf-8", "replace")
            if e.code == 429:
                if "PerDay" in msg or "per day" in msg.lower():
                    raise DailyLimit(f"{model}: {_limit_info(msg)}")
                m = re.search(r'"retryDelay":\s*"(\d+)', msg)
                wait = int(m.group(1)) + 2 if m else 20 * attempt
                print(f"  [Google: too many requests this minute, waiting {wait}s]", flush=True)
                time.sleep(wait)
                continue
            if e.code >= 500:
                time.sleep(10 * attempt)
                continue
            print(f"\n  Google refused it ({e.code}): {msg[:500]}")
            return None
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"  [network: {e}, retry]", flush=True)
            time.sleep(5 * attempt)
    return None


def list_models():
    try:
        res = call("GET", "/models?pageSize=1000")
    except urllib.error.HTTPError as e:
        print("Google refused the key:", e.code, e.read().decode("utf-8", "replace")[:400])
        sys.exit(1)
    return [m.get("name", "").replace("models/", "") for m in res.get("models", [])]


def pick(models, wanted, test):
    for m in wanted:
        if m in models:
            return m
    rest = sorted(m for m in models if test(m))
    return rest[-1] if rest else None


def speak(model, voice, lines):
    """one request: [lines] in [voice] -> (pcm, rate) or None"""
    body = {
        "contents": [{"parts": [{"text": DIRECTION + "\n".join(lines)}]}],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}},
        },
    }
    res = generate(model, body)
    if res is None:
        return None
    try:
        part = res["candidates"][0]["content"]["parts"][0]["inlineData"]
    except (KeyError, IndexError):
        print(f"  no audio in the answer: {json.dumps(res)[:300]}")
        return None
    mime = part.get("mimeType", "")
    rate = int(mime.split("rate=")[1].split(";")[0]) if "rate=" in mime else 24000
    return base64.b64decode(part["data"]), rate


def wav(pcm, rate):
    """16-bit mono PCM (what Gemini returns) -> .wav bytes"""
    return (b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVEfmt "
            + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16)
            + b"data" + struct.pack("<I", len(pcm)) + pcm)


# ------------------------------------------------------------------ checking the clips


def norm(t):
    """compare Arabic loosely: no tashkeel, punctuation or spaces; common spelling variants equal"""
    t = TASHKEEL.sub("", t)
    for a, b in (("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ى", "ي"), ("ة", "ه"), ("ؤ", "و"), ("ئ", "ي")):
        t = t.replace(a, b)
    return re.sub(r"[^ء-ي]", "", t)


def lengths_ok(clips, rate, lines):
    """every clip's share of the time should be close to its line's share of the text"""
    total = sum(audio_split.seconds(c, rate) for c in clips)
    chars = [len(norm(l)) + 4 for l in lines]
    for c, n in zip(clips, chars):
        r = (audio_split.seconds(c, rate) / total) / (n / sum(chars))
        if r > 3.0 or r < 0.3:
            return False
    return True


def heard(model, clips, rate):
    """what Gemini hears in each clip (list of texts) or None"""
    parts = [{"text": f"Transcribe each of the {len(clips)} audio clips below exactly as spoken. They are "
                      "Egyptian Arabic: write them in Arabic letters the way Egyptians write, numbers as "
                      "words. Answer with ONLY a JSON array of strings, one per clip, in order."}]
    for i, c in enumerate(clips, 1):
        parts.append({"text": f"Clip {i}:"})
        parts.append({"inlineData": {"mimeType": "audio/wav", "data": base64.b64encode(wav(c, rate)).decode()}})
    res = generate(model, {"contents": [{"parts": parts}],
                           "generationConfig": {"responseMimeType": "application/json"}})
    if res is None:
        return None
    try:
        out = json.loads(res["candidates"][0]["content"]["parts"][0]["text"])
        return [str(x) for x in out] if isinstance(out, list) and len(out) == len(clips) else None
    except (KeyError, IndexError, ValueError):
        return None


def matches(said, line):
    if re.search(r"[A-Za-z]{3,}", said):  # read the English instruction out loud
        return False
    return difflib.SequenceMatcher(None, norm(said), norm(line)).ratio() >= 0.5


# ------------------------------------------------------------------ saving


def mp3(pcm, rate):
    import lameenc

    e = lameenc.Encoder()
    e.set_bit_rate(MP3_KBPS)
    e.set_in_sample_rate(rate)
    e.set_channels(1)
    e.set_quality(2)
    return e.encode(pcm) + e.flush()


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


# ------------------------------------------------------------------ recording


def record():
    try:
        import lameenc  # noqa: F401
    except ImportError:
        print("The MP3 encoder is missing. Run:  python -m pip install lameenc")
        sys.exit(1)
    names = [a.lower() for a in sys.argv[sys.argv.index("--record") + 1:] if not a.startswith("--")]
    folders = [f for f in VOICES if not names or f in names]
    if not folders:
        print("Unknown voice. Voices: " + ", ".join(VOICES))
        sys.exit(1)
    check = "--no-check" not in sys.argv
    pieces = load_pieces()
    models = list_models()
    tts_model = pick(models, TTS_MODELS, lambda m: "tts" in m)
    check_model = pick(models, CHECK_MODELS, lambda m: "flash" in m and not any(
        x in m for x in ("tts", "image", "live", "audio", "embed", "thinking")))
    if not tts_model:
        print("This key cannot use a Gemini text-to-speech model (see --models).")
        sys.exit(1)
    if check and not check_model:
        print("No Gemini model to check the clips with; recording without the check.")
        check = False
    print(f"voice model: {tts_model}" + (f", checked by: {check_model}" if check else ", not checked"))

    recorded = load_json(RECORDED)
    manifest = load_json(MANIFEST)
    requests = 0

    def record_batch(folder, voice, batch, out_dir, state):
        """records [batch] (list of (key, text)); True when all were saved"""
        nonlocal requests
        texts = [TASHKEEL.sub("", t) for _, t in batch]
        # a big batch gets one try, then it is cut in half; a single line gets two tries
        for attempt in range(1 if len(batch) > 1 else 2):
            got = speak(tts_model, voice, texts)
            requests += 1
            if not got:
                continue
            pcm, rate = got
            clips = [pcm] if len(batch) == 1 else audio_split.split(pcm, rate, len(batch))
            if clips is None or not lengths_ok(clips, rate, texts):
                continue
            bad = []
            if check:
                said = heard(check_model, clips, rate)
                requests += 1
                if said is None:
                    continue
                bad = [i for i, (s, t) in enumerate(zip(said, texts)) if not matches(s, t)]
                if len(bad) > len(batch) // 2:  # most are wrong: the cut itself is off
                    continue
            for i, ((k, t), c) in enumerate(zip(batch, clips)):
                if i in bad:
                    continue
                with open(os.path.join(out_dir, k + ".mp3"), "wb") as f:
                    f.write(mp3(c, rate))
                state[k] = t
            save_json(RECORDED, recorded, ensure_ascii=False, indent=1)
            if bad:
                # the good clips are kept; only the wrong lines are recorded again
                print(f"  {len(bad)} clip(s) did not match their line, recording only those again", flush=True)
                return record_batch(folder, voice, [batch[i] for i in bad], out_dir, state)
            return True
        if len(batch) >= 4:  # cut in half and try the halves (smaller: line by line)
            h = len(batch) // 2
            a = record_batch(folder, voice, batch[:h], out_dir, state)
            b = record_batch(folder, voice, batch[h:], out_dir, state)
            return a and b
        if len(batch) > 1:
            ok = [record_batch(folder, voice, [one], out_dir, state) for one in batch]
            return all(ok)
        print(f"  could not record: {batch[0][1]}")
        return False

    try:
        for folder in folders:
            voice, gender = VOICES[folder]
            out_dir = os.path.join(ASSET_DIR, folder)
            os.makedirs(out_dir, exist_ok=True)
            state = recorded.setdefault(folder, {})
            todo = [(k, t) for k, t in pieces.items()
                    if state.get(k) != t or not os.path.exists(os.path.join(out_dir, k + ".mp3"))]
            print(f"{voice} ({gender}): {len(pieces) - len(todo)} done, {len(todo)} to record")
            failed_in_row = 0
            for i in range(0, len(todo), BATCH):
                batch = todo[i:i + BATCH]
                failed_in_row = 0 if record_batch(folder, voice, batch, out_dir, state) else failed_in_row + 1
                if failed_in_row >= 2:
                    # something keeps going wrong with this voice: do not burn the daily limit
                    print(f"  {voice}: two batches in a row failed, stopping this voice for now")
                    break
                done = sum(1 for k in pieces if k in state and os.path.exists(os.path.join(out_dir, k + ".mp3")))
                print(f"  {voice}: {done}/{len(pieces)}   ({requests} requests so far)", flush=True)
            # clips of text nobody uses any more
            for name in os.listdir(out_dir):
                if name.endswith(".mp3") and name[:-4] not in pieces:
                    os.remove(os.path.join(out_dir, name))
            recorded[folder] = {k: v for k, v in state.items() if k in pieces}
            save_json(RECORDED, recorded, ensure_ascii=False, indent=1)
            complete = all(recorded[folder].get(k) == t and os.path.exists(os.path.join(out_dir, k + ".mp3"))
                           for k, t in pieces.items())
            if complete:
                manifest[folder] = sorted(pieces)
                save_json(MANIFEST, manifest, indent=1)
                print(f"{voice}: complete, now in the app (manifest.json)")
            else:
                manifest.pop(folder, None)
                save_json(MANIFEST, manifest, indent=1)
                print(f"{voice}: not complete yet (run the same command again)")
    except DailyLimit as e:
        save_json(RECORDED, recorded, ensure_ascii=False, indent=1)
        print(f"\nGoogle's daily limit is used up ({e}).\n"
              f"Everything recorded so far is saved ({requests} requests this run).\n"
              "Run the same command tomorrow: it continues where it stopped.")
        if check and check_model in str(e):
            print("It was the CHECKING model's limit: add --no-check to keep recording today without the check.")
        return
    print("Done. Build the app again to hear the voices.")


# ------------------------------------------------------------------ samples


def sample():
    voices = [v for v, _ in VOICES.values()]
    if "--voices" in sys.argv:
        voices = [a for a in sys.argv[sys.argv.index("--voices") + 1:] if not a.startswith("--")]
    model = pick(list_models(), TTS_MODELS, lambda m: "tts" in m)
    if not model:
        print("This key cannot use a Gemini text-to-speech model (see --models).")
        sys.exit(1)
    gender = {v: g for v, g in VOICES.values()}
    print(f"model: {model}, voices: {', '.join(voices)}")
    print("Each voice can take up to a minute or two (Google makes all 8 lines at once). Don't press Ctrl+C.")
    os.makedirs(SAMPLE_DIR, exist_ok=True)
    try:
        for v in voices:
            print(f"  {v} ({gender.get(v, '?')}) ... working", end="", flush=True)
            start = time.time()
            got = speak(model, v, SAMPLE_LINES)
            if got:
                with open(os.path.join(SAMPLE_DIR, f"{v}_{gender.get(v, 'voice')}.wav"), "wb") as f:
                    f.write(wav(*got))
                print(f" saved ({time.time() - start:.0f}s)")
    except DailyLimit:
        print("\nGoogle's daily limit for this key is used up. Try again tomorrow.")
    with open(os.path.join(SAMPLE_DIR, "lines.txt"), "w", encoding="utf-8") as f:
        f.write("Every file says these lines, in this order:\n" + "\n".join(SAMPLE_LINES) + "\n")
    print(f"Listen in {SAMPLE_DIR}/ and tell which voice sounds most like a normal Egyptian.")


if __name__ == "__main__":
    if "--models" in sys.argv:
        print("\n".join(m for m in list_models() if "tts" in m) or "no TTS models for this key")
    elif "--record" in sys.argv:
        record()
    elif "--sample" in sys.argv:
        sample()
    else:
        print(__doc__)
