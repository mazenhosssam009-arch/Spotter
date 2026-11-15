"""A female Egyptian voice made on your own PC with the open-source VoiceTut-TTS model, copying
the voice of Gemini's Zephyr (no training: VoiceTut listens to a 5 s clip and speaks like it).
The clip is lines 4-5 of Gemini's sample, tool/try/gemini/Zephyr_female.wav (the version picked
by ear in tool/try/local/compare.html). Spellings: the same say_as() as the VoiceTut server.

Shows in the app's voice settings as "VoiceTut Clone" (folder assets/voice/ar_eg/voicetut_clone).
A trial voice: keep it, rename it, or delete it after listening in the app.

Use (Python of tool/.venv, from the project folder; CPU, about 18 s a line, ~1.5 h for all):
    tool\\.venv\\Scripts\\python tool/make_egyptian_voice_voicetut_clone.py
Re-running only makes new or changed lines; the voice appears in the app (manifest.json) when
all its lines are made. Build the app again afterwards.
"""

import json
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "voicetut"))

FOLDER = "voicetut_clone"
VOICE, REF_LINES = "Zephyr", "4-5"
ASSET_DIR = os.path.join("assets", "voice", "ar_eg")
PIECES = os.path.join(ASSET_DIR, "pieces.txt")
MANIFEST = os.path.join(ASSET_DIR, "manifest.json")
RECORDED = os.path.join(ASSET_DIR, "recorded_voicetut.json")
REF_DIR = os.path.join(HERE, "voice_refs", FOLDER)


def load_json(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")


def load_pieces():
    if not os.path.exists("pubspec.yaml"):
        sys.exit("Run this from the project folder (the one with pubspec.yaml).")
    pieces = {}
    with open(PIECES, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if "\t" in line:
                k, t = line.split("\t", 1)
                if k and t.strip():
                    pieces[k] = t
    return pieces


def main():
    import torch
    from server import STYLE, mp3, say_as
    from try_local_voices import gemini_ref
    from voicetut_tts import VoiceTutTTS

    pieces = load_pieces()
    os.makedirs(REF_DIR, exist_ok=True)
    ref, ref_text = gemini_ref(VOICE, REF_DIR, REF_LINES)
    out_dir = os.path.join(ASSET_DIR, FOLDER)
    os.makedirs(out_dir, exist_ok=True)
    recorded = load_json(RECORDED)
    state = recorded.setdefault(FOLDER, {})
    todo = [(k, t) for k, t in pieces.items()
            if state.get(k) != t or not os.path.exists(os.path.join(out_dir, k + ".mp3"))]
    print(f"{FOLDER}: {len(pieces) - len(todo)} done, {len(todo)} to make", flush=True)

    if todo:
        tts = VoiceTutTTS.from_pretrained("mohammedaly22/VoiceTut-TTS", device="cpu", dtype="float32")
        wav = os.path.join(tempfile.gettempdir(), f"{FOLDER}_line.wav")
        start = time.time()
        for n, (k, t) in enumerate(todo, 1):
            with torch.inference_mode():
                torch.manual_seed(0)
                tts.synthesize(say_as(t), ref_audio=ref, ref_text=ref_text, output=wav, **STYLE)
            with open(os.path.join(out_dir, k + ".mp3"), "wb") as f:
                f.write(mp3(wav))
            state[k] = t
            if n % 10 == 0 or n == len(todo):
                save_json(RECORDED, recorded)
                left = (time.time() - start) / n * (len(todo) - n)
                print(f"  {n}/{len(todo)}   about {left / 60:.0f} min left", flush=True)
        os.remove(wav)

    # clips of lines the app no longer says
    for name in os.listdir(out_dir):
        if name.endswith(".mp3") and name[:-4] not in pieces:
            os.remove(os.path.join(out_dir, name))
    recorded[FOLDER] = {k: v for k, v in state.items() if k in pieces}
    save_json(RECORDED, recorded)
    if all(recorded[FOLDER].get(k) == t and os.path.exists(os.path.join(out_dir, k + ".mp3"))
           for k, t in pieces.items()):
        manifest = load_json(MANIFEST)
        manifest[FOLDER] = sorted(pieces)
        with open(MANIFEST, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=1)  # no newline at the end, like the other voice scripts
        print(f"{FOLDER}: complete, now in the app (manifest.json). Build the app again.")


if __name__ == "__main__":
    main()
