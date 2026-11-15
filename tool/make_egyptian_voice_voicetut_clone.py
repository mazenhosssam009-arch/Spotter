"""A female Egyptian voice made on your own PC with the open-source VoiceTut-TTS model, copying
the voice of Gemini's Zephyr (no training: VoiceTut listens to a 5 s clip and speaks like it).
The clip is lines 4-5 of Gemini's sample, tool/try/gemini/Zephyr_female.wav (the version picked
by ear in tool/try/local/compare.html). Spellings: the same say_as() as the VoiceTut server, then
the exercise names in English letters (said in English), and the tashkeel is KEPT: VoiceTut's own
text clean-up (which removes almost all tashkeel) is skipped. Both picked by ear.

Shows in the app's voice settings as "VoiceTut Clone" (folder assets/voice/ar_eg/voicetut_clone).
A trial voice: keep it, rename it, or delete it after listening in the app.

Use (Python of tool/.venv, from the project folder; CPU, about 18 s a line, ~1.5 h for all):
    tool\\.venv\\Scripts\\python tool/make_egyptian_voice_voicetut_clone.py
Re-running only makes new or changed lines (also when a spelling in say_as() changes); the voice
appears in the app (manifest.json) when all its lines are made. Build the app again afterwards.
tool/check_voice_whisper.py checks the clips with Whisper and makes the wrong ones again with
another take (seed); the take of each line is kept in recorded_voicetut.json.
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
# how the lines are made; when it changes every line is made again
HOW = "tashkeel kept, English exercise names"


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


def spoken(text):
    """the app's line -> what VoiceTut is given"""
    from server import say_as
    from try_local_voices import english
    return english(say_as(text))


def load_model():
    from voicetut_tts import VoiceTutTTS
    return VoiceTutTTS.from_pretrained("mohammedaly22/VoiceTut-TTS", device="cpu", dtype="float32")


def reference():
    """(ref clip, its text): lines REF_LINES of Gemini's sample"""
    from try_local_voices import gemini_ref
    os.makedirs(REF_DIR, exist_ok=True)
    return gemini_ref(VOICE, REF_DIR, REF_LINES)


def make(tts, said, ref, ref_text, seed, wav, out_mp3):
    """one clip: `said` (from spoken()) with take `seed`"""
    import torch
    from server import STYLE, mp3
    with torch.inference_mode():
        torch.manual_seed(seed)
        tts.synthesize(said, ref_audio=ref, ref_text=ref_text, normalize=False, output=wav, **STYLE)
    with open(out_mp3, "wb") as f:
        f.write(mp3(wav))


def main():
    pieces = load_pieces()
    ref, ref_text = reference()
    out_dir = os.path.join(ASSET_DIR, FOLDER)
    os.makedirs(out_dir, exist_ok=True)
    recorded = load_json(RECORDED)
    if recorded.get(FOLDER + "_how") != HOW:
        recorded[FOLDER] = {}  # made another way: make every line again
        recorded[FOLDER + "_how"] = HOW
    # key -> the text the clip was made from (what VoiceTut was given)
    state = recorded.setdefault(FOLDER, {})
    seeds = recorded.setdefault(FOLDER + "_seed", {})
    said = {k: spoken(t) for k, t in pieces.items()}
    todo = [(k, said[k]) for k in pieces
            if state.get(k) != said[k] or not os.path.exists(os.path.join(out_dir, k + ".mp3"))]
    print(f"{FOLDER}: {len(pieces) - len(todo)} done, {len(todo)} to make", flush=True)

    if todo:
        tts = load_model()
        wav = os.path.join(tempfile.gettempdir(), f"{FOLDER}_line.wav")
        start = time.time()
        for n, (k, t) in enumerate(todo, 1):
            seeds.pop(k, None)  # a new text starts again from take 0
            make(tts, t, ref, ref_text, 0, wav, os.path.join(out_dir, k + ".mp3"))
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
    recorded[FOLDER + "_seed"] = {k: v for k, v in seeds.items() if k in pieces}
    save_json(RECORDED, recorded)
    if all(recorded[FOLDER].get(k) == said[k] and os.path.exists(os.path.join(out_dir, k + ".mp3"))
           for k in pieces):
        manifest = load_json(MANIFEST)
        manifest[FOLDER] = sorted(pieces)
        with open(MANIFEST, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=1)  # no newline at the end, like the other voice scripts
        print(f"{FOLDER}: complete, now in the app (manifest.json). Build the app again.")


if __name__ == "__main__":
    main()
