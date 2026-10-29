"""The Egyptian Arabic voices of the voice coach, made on your own PC with the open-source
NAMAA-Egyptian-TTS model (MIT license, commercial use allowed, built on Resemble AI's
Chatterbox). No API key, no daily limit; a GPU makes it fast, a CPU works too (slower).
Model: https://huggingface.co/NAMAA-Space/NAMAA-Egyptian-TTS

The model speaks in the voice of a short REFERENCE recording (5-15 s of clean speech):
  namaa_female  tool/voice_refs/namaa_female.wav  (downloaded: the voice of the NAMAA demo)
  namaa_male    tool/voice_refs/namaa_male.wav    (record one: see below)
Only use the voice of someone who agreed to it. Male reference: a teammate reads a few
natural Egyptian sentences for ~10 seconds in a quiet room; save it as a .wav at that path.

Setup (once, in a virtual environment, from the project folder):
    python -m venv tool/.venv
    tool/.venv/Scripts/activate            (Windows; macOS/Linux: source tool/.venv/bin/activate)
    pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu121   (NVIDIA GPU)
    pip install chatterbox-tts lameenc huggingface_hub safetensors
    pip install faster-whisper             (optional: checks every clip says its line)

Use:
    dart run tool/make_egyptian_voice.dart --list              (the lines the app says)
    python tool/make_egyptian_voice_namaa.py --sample          (8 coach lines per voice -> tool/try/namaa/)
    python tool/make_egyptian_voice_namaa.py --record          (every line, both voices)
    python tool/make_egyptian_voice_namaa.py --record namaa_male
Options: --check (Whisper listens to every clip and re-makes the wrong ones), --cpu.
Re-running only makes new or changed lines; a voice appears in the app (manifest.json)
when all its lines are made. Lines Whisper still doubted are listed in
tool/try/namaa/<voice>_listen.txt: listen to those before shipping.
"""

import array
import json
import os
import re
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ASSET_DIR = os.path.join("assets", "voice", "ar_eg")
PIECES = os.path.join(ASSET_DIR, "pieces.txt")
MANIFEST = os.path.join(ASSET_DIR, "manifest.json")
RECORDED = os.path.join(ASSET_DIR, "recorded_namaa.json")
TRY_DIR = os.path.join("tool", "try", "namaa")
REF_DIR = os.path.join("tool", "voice_refs")
REPO_ID = "NAMAA-Space/NAMAA-Egyptian-TTS"

# clip folder -> (gender, reference file, where to download it if missing)
VOICES = {
    "namaa_female": ("female", os.path.join(REF_DIR, "namaa_female.wav"),
                     "https://huggingface.co/spaces/omarelshehy/NAMAA-Egyptian-Voice/resolve/main/female_voice.wav"),
    "namaa_male": ("male", os.path.join(REF_DIR, "namaa_male.wav"), None),
}
# how it speaks (the demo's defaults; exaggeration up = more energy)
STYLE = {"exaggeration": 0.5, "temperature": 0.8, "cfg_weight": 0.5}
SEEDS = [1, 7, 42]  # a wrong clip is made again with the next seed
MP3_KBPS = 48

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


# ------------------------------------------------------------------ small helpers


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


def norm(t):
    """compare Arabic loosely: no tashkeel, punctuation or spaces; common spelling variants equal"""
    t = TASHKEEL.sub("", t)
    for a, b in (("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ى", "ي"), ("ة", "ه"), ("ؤ", "و"), ("ئ", "ي")):
        t = t.replace(a, b)
    return re.sub(r"[^ء-ي]", "", t)


def similarity(said, line):
    import difflib

    return difflib.SequenceMatcher(None, norm(said), norm(line)).ratio()


def reference(folder):
    gender, path, url = VOICES[folder]
    if os.path.exists(path):
        return path
    if url:
        os.makedirs(REF_DIR, exist_ok=True)
        print(f"downloading the {folder} reference voice ...")
        urllib.request.urlretrieve(url, path)
        return path
    print(f"{folder}: no reference recording at {path}.\n"
          f"  Record ~10 s of a {gender} Egyptian speaker (who agreed to it) reading natural Egyptian\n"
          f"  sentences in a quiet room, save it as that .wav file, then run this again.")
    return None


# ------------------------------------------------------------------ the model


class Namaa:
    def __init__(self, cpu=False):
        import torch
        from huggingface_hub import snapshot_download
        from safetensors.torch import load_file

        try:
            from chatterbox.mtl_tts import ChatterboxMultilingualTTS
        except ImportError:
            sys.exit("chatterbox is missing. Run:  pip install chatterbox-tts")
        self.torch = torch
        self.device = "cpu" if cpu or not torch.cuda.is_available() else "cuda"
        print(f"loading NAMAA-Egyptian-TTS on {self.device} (the first time downloads a few GB) ...")
        ckpt = snapshot_download(repo_id=REPO_ID, repo_type="model")
        self.model = ChatterboxMultilingualTTS.from_pretrained(device=self.device)
        self.model.t3.load_state_dict(load_file(os.path.join(ckpt, "t3_mtl23ls_v2.safetensors"), device=self.device))
        self.model.t3.to(self.device).eval()
        self.sr = self.model.sr

    def say(self, text, ref, seed):
        """16-bit mono PCM bytes of [text] in the voice of [ref]"""
        self.torch.manual_seed(seed)
        if self.device == "cuda":
            self.torch.cuda.manual_seed_all(seed)
        wav = self.model.generate(text, language_id="ar", audio_prompt_path=ref, **STYLE)
        samples = wav.squeeze(0).clamp(-1, 1).cpu().numpy()
        return (samples * 32767).astype("int16").tobytes()


def trim(pcm, rate, pad_ms=60):
    """cut the silence before and after the speech, keep a little"""
    a = array.array("h")
    a.frombytes(pcm)
    if not a:
        return pcm
    loud = sorted(abs(x) for x in a[:: max(1, len(a) // 4000)])[-1]
    quiet = max(300, loud * 0.05)
    first = next((i for i, x in enumerate(a) if abs(x) > quiet), 0)
    last = next((i for i in range(len(a) - 1, -1, -1) if abs(a[i]) > quiet), len(a) - 1)
    pad = rate * pad_ms // 1000
    return a[max(0, first - pad): min(len(a), last + pad)].tobytes()


def mp3(pcm, rate):
    import lameenc

    e = lameenc.Encoder()
    e.set_bit_rate(MP3_KBPS)
    e.set_in_sample_rate(rate)
    e.set_channels(1)
    e.set_quality(2)
    return e.encode(pcm) + e.flush()


def wav_bytes(pcm, rate):
    import struct

    return (b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVEfmt "
            + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16)
            + b"data" + struct.pack("<I", len(pcm)) + pcm)


class Checker:
    """Whisper (faster-whisper) listens to a clip and says what it heard"""

    def __init__(self, cpu=False):
        try:
            from faster_whisper import WhisperModel
        except ImportError:
            sys.exit("--check needs faster-whisper. Run:  pip install faster-whisper")
        import torch

        gpu = not cpu and torch.cuda.is_available()
        print("loading Whisper for the check ...")
        self.model = WhisperModel("large-v3" if gpu else "small", device="cuda" if gpu else "cpu",
                                  compute_type="float16" if gpu else "int8")

    def heard(self, pcm, rate):
        import io

        segs, _ = self.model.transcribe(io.BytesIO(wav_bytes(pcm, rate)), language="ar", beam_size=5)
        return " ".join(s.text for s in segs)


# ------------------------------------------------------------------ commands


def voices_from_args(flag):
    names = [a for a in sys.argv[sys.argv.index(flag) + 1:] if not a.startswith("--")]
    for n in names:
        if n not in VOICES:
            sys.exit(f"Unknown voice {n}. Voices: {', '.join(VOICES)}")
    return names or list(VOICES)


def sample():
    tts = Namaa(cpu="--cpu" in sys.argv)
    for folder in voices_from_args("--sample"):
        ref = reference(folder)
        if not ref:
            continue
        out = os.path.join(TRY_DIR, folder)
        os.makedirs(out, exist_ok=True)
        for i, line in enumerate(SAMPLE_LINES, 1):
            pcm = trim(tts.say(line, ref, SEEDS[0]), tts.sr)
            with open(os.path.join(out, f"{i:02d}.wav"), "wb") as f:
                f.write(wav_bytes(pcm, tts.sr))
        print(f"  {out}")
    with open(os.path.join(TRY_DIR, "lines.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(f"{i:02d}  {l}" for i, l in enumerate(SAMPLE_LINES, 1)) + "\n")
    print(f"Listen in {TRY_DIR}/ (lines.txt says what each number is).")


def record():
    try:
        import lameenc  # noqa: F401
    except ImportError:
        sys.exit("The MP3 encoder is missing. Run:  pip install lameenc")
    pieces = load_pieces()
    folders = voices_from_args("--record")
    cpu = "--cpu" in sys.argv
    checker = Checker(cpu) if "--check" in sys.argv else None
    tts = None
    recorded = load_json(RECORDED)
    manifest = load_json(MANIFEST)
    os.makedirs(TRY_DIR, exist_ok=True)

    for folder in folders:
        ref = reference(folder)
        if not ref:
            continue
        gender = VOICES[folder][0]
        out_dir = os.path.join(ASSET_DIR, folder)
        os.makedirs(out_dir, exist_ok=True)
        state = recorded.setdefault(folder, {})
        todo = [(k, t) for k, t in pieces.items()
                if state.get(k) != t or not os.path.exists(os.path.join(out_dir, k + ".mp3"))]
        print(f"{folder} ({gender}): {len(pieces) - len(todo)} done, {len(todo)} to make")
        doubtful = []
        start = time.time()
        for n, (k, t) in enumerate(todo, 1):
            if tts is None:
                tts = Namaa(cpu)
            text = TASHKEEL.sub("", t)
            best, best_score = None, -1.0
            for seed in SEEDS if checker else SEEDS[:1]:
                pcm = trim(tts.say(text, ref, seed), tts.sr)
                if not checker:
                    best = pcm
                    break
                score = similarity(checker.heard(pcm, tts.sr), text)
                if score > best_score:
                    best, best_score = pcm, score
                if score >= 0.6:
                    break
            if checker and best_score < 0.6:
                doubtful.append(f"{k}\t{best_score:.2f}\t{t}")
            with open(os.path.join(out_dir, k + ".mp3"), "wb") as f:
                f.write(mp3(best, tts.sr))
            state[k] = t
            if n % 10 == 0 or n == len(todo):
                save_json(RECORDED, recorded, ensure_ascii=False, indent=1)
                left = (time.time() - start) / n * (len(todo) - n)
                print(f"  {folder}: {n}/{len(todo)}   about {left / 60:.0f} min left", flush=True)
        # clips of lines the app no longer says
        for name in os.listdir(out_dir):
            if name.endswith(".mp3") and name[:-4] not in pieces:
                os.remove(os.path.join(out_dir, name))
        recorded[folder] = {k: v for k, v in state.items() if k in pieces}
        save_json(RECORDED, recorded, ensure_ascii=False, indent=1)
        if doubtful:
            path = os.path.join(TRY_DIR, f"{folder}_listen.txt")
            with open(path, "w", encoding="utf-8") as f:
                f.write("Whisper doubted these clips (file, score, line). Listen to them:\n" + "\n".join(doubtful) + "\n")
            print(f"  {len(doubtful)} clip(s) to listen to: {path}")
        if all(recorded[folder].get(k) == t and os.path.exists(os.path.join(out_dir, k + ".mp3"))
               for k, t in pieces.items()):
            manifest[folder] = sorted(pieces)
            save_json(MANIFEST, manifest, indent=1)
            print(f"{folder}: complete, now in the app (manifest.json)")
    print("Done. Build the app again to hear the voices.")


if __name__ == "__main__":
    if "--record" in sys.argv:
        record()
    elif "--sample" in sys.argv:
        sample()
    else:
        print(__doc__)
