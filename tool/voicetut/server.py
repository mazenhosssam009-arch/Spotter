"""VoiceTut-TTS server for the app's "online voice" (open source, Apache-2.0).
Model: https://huggingface.co/mohammedaly22/VoiceTut-TTS (19 Egyptian voices, needs a GPU).
Run it in Google Colab with tool/voicetut/VoiceTut_server.ipynb (free T4 GPU).

  GET  /            -> {"ok": true, "speakers": [...]}
  POST /tts         {"text": "...", "speaker": "Yasmin"} -> MP3 of the line

The app sends its own Arabic text; say_as() below turns it into what VoiceTut says right
(tashkeel and spellings checked by ear in the VoiceTut demo). Fix a word here, run the
notebook again, and download the voice again in the app: no new app build is needed.
"""

import hashlib
import io
import os
import re
import threading

SPEAKERS = {
    "male": ["Ahmed", "Ali", "Hassan", "Karim", "Mahmoud", "Mohammed", "Mostafa", "Ramy", "Shaker",
             "Tareq", "Yehia", "Youssef"],
    "female": ["Hadeer", "Hanan", "Mariam", "Rana", "Sarah", "Yasmin", "Yara"],
}
CACHE = "/content/voicetut_cache"
RATE = 24000
TASHKEEL = re.compile(r"[ً-ْٰ]")

# whole lines said differently (the app text without tashkeel -> what VoiceTut says)
LINES = {
    "الراحة خلصت، جاهز للست اللي جاي؟": "الرَّاحَة خِلْصِت. إِنْتَ جَاهِز؟",
    "الراحة خلصت، جاهز للمجموعة اللي جاية؟": "الرَّاحَة خِلْصِت. إِنْتَ جَاهِز؟",
    "قول يلا، أو وقت زيادة": "ءُول جَاهِز. وَلَّا عَايِز وَءْت زِيَادَة؟",
    "بهدوء، متستعجلش في الحركة": "بِرَّاحَة، اِهْدَا",
}
# phrases inside lines (without tashkeel -> with the tashkeel VoiceTut needs)
PHRASES = [
    ("ضم كوعك لجوه شوية", "ضُمّ كُوعَك لِجُوَّه شُوَيَّة"),
    ("متخليش ركبتك تدخل لجوه", "مَتْخَلِّيش رُكْبِتَك تِدْخُل لِجُوَّه"),
    ("خلي ضهرك مستقيم", "خَلِّي ضَهْرَك مُسْتَقِيم"),
    ("تكرارات", "عَدَّات"), ("تكرارتين", "عَدِّتين"), ("تكرارة", "عَدَّة"),
    ("بهدوء، متستعجلش في الحركة", "بِرَّاحَة، اِهْدَا"),
]
# numbers: your spelling (talattashar and etnashar checked in the VoiceTut demo)
UNITS = {"واحد": "وَاحِد", "اتنين": "اِتْنِين", "تلاتة": "تَلَاتَة", "أربعة": "أَرْبَعَة", "خمسة": "خَمْسَة",
         "ستة": "سِتَّة", "سبعة": "سَبْعَة", "تمانية": "تَمَانْيَة", "تسعة": "تِسْعَة"}
TEENS = {"عشرة": "عَشَرَة", "حداشر": "حِدَاشَر", "اتناشر": "اِتْنَاشَر", "تلاتطاشر": "تَلَتّاشَر",
         "أربعطاشر": "أَرْبَعْتَاشَر", "خمسطاشر": "خَمَسْتَاشَر", "ستاشر": "سِتَّاشَر", "سبعطاشر": "سَبَعْتَاشَر",
         "تمانطاشر": "تَمَنْتَاشَر", "تسعطاشر": "تِسَعْتَاشَر"}
TENS = {"عشرين": "عِشْرِين", "تلاتين": "تَلَاتِين", "أربعين": "أَرْبِعِين", "خمسين": "خَمْسِين",
        "ستين": "سِتِّين", "سبعين": "سَبْعِين", "تمانين": "تَمَانِين", "تسعين": "تِسْعِين", "مية": "مِيَّة"}


def say_as(text):
    """the app's line -> what VoiceTut reads"""
    plain = TASHKEEL.sub("", text).strip()
    bare = plain.strip(" .!،")
    one = {**UNITS, **TEENS, **TENS}
    if bare in one:
        return one[bare]
    m = re.fullmatch(r"(\S+) و(\S+)", bare)
    if m and m.group(1) in UNITS and m.group(2) in TENS:
        return f"{UNITS[m.group(1)]} وِ{TENS[m.group(2)]}"
    if plain in LINES:
        return LINES[plain]
    # "يلا يا بطل" is not said (as with the recorded voices)
    out = re.sub(r"،\s*يَ?لّ?َ?ا يا بَ?طَ?ل!", "!", text)
    out = re.sub(r"يَ?لّ?َ?ا يا بَ?طَ?ل،\s*", "", out).strip() or text
    for a, b in PHRASES:
        if a in TASHKEEL.sub("", out):
            # replace the phrase whatever tashkeel the app gave it
            pattern = "".join(re.escape(ch) + "[ً-ْٰ]*" for ch in a)
            out = re.sub(pattern, b, out)
    return out


# ------------------------------------------------------------------ model + server

_tts = None
_lock = threading.Lock()


def model():
    global _tts
    if _tts is None:
        from voicetut_tts import VoiceTutTTS

        _tts = VoiceTutTTS.from_pretrained("mohammedaly22/VoiceTut-TTS")
    return _tts


def mp3(path_wav):
    """WAV file -> MP3 bytes (64 kbps, small enough for a phone)"""
    import lameenc
    import numpy as np
    import soundfile as sf

    audio, rate = sf.read(path_wav, dtype="int16")
    if audio.ndim > 1:
        audio = audio[:, 0]
    enc = lameenc.Encoder()
    enc.set_bit_rate(64)
    enc.set_in_sample_rate(rate)
    enc.set_channels(1)
    enc.set_quality(2)
    return enc.encode(np.ascontiguousarray(audio).tobytes()) + enc.flush()


def synthesize(text, speaker):
    os.makedirs(CACHE, exist_ok=True)
    spoken = say_as(text)
    name = hashlib.sha1(f"{speaker}|{spoken}".encode()).hexdigest()[:16]
    cached = os.path.join(CACHE, name + ".mp3")
    if os.path.exists(cached):
        return open(cached, "rb").read()
    wav = os.path.join(CACHE, name + ".wav")
    with _lock:  # one line at a time on the GPU
        model().synthesize(spoken, speaker=speaker, output=wav)
    data = mp3(wav)
    open(cached, "wb").write(data)
    os.remove(wav)
    return data


def app():
    from fastapi import FastAPI, HTTPException
    from fastapi.responses import Response
    from pydantic import BaseModel

    api = FastAPI(title="VoiceTut for Spotter")

    class Line(BaseModel):
        text: str
        speaker: str = "Yasmin"

    @api.get("/")
    def info():
        return {"ok": True, "speakers": SPEAKERS}

    @api.post("/tts")
    def tts(line: Line):
        if line.speaker not in SPEAKERS["male"] + SPEAKERS["female"]:
            raise HTTPException(400, f"unknown speaker {line.speaker}")
        if not line.text.strip():
            raise HTTPException(400, "empty text")
        return Response(synthesize(line.text, line.speaker), media_type="audio/mpeg")

    return api


if __name__ == "__main__":
    import uvicorn

    model()  # load before the first request
    uvicorn.run(app(), host="0.0.0.0", port=8000)
