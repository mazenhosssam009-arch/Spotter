# Voice coach: setup

The voice coach speaks form warnings, counts reps, and handles the rest timer and set
summaries in **English** or **Egyptian Arabic**, with a male or female voice. The first
time the app opens, the user picks the language. They can change it any time from the
speaker icon on the menu or on the trainer screen.

## 1. pubspec.yaml

```yaml
dependencies:
  flutter_tts: ^4.2.0          # text to speech (phone voices, works offline)
  audio_session: ^0.2.0        # lowers or pauses the user's music, detects headphones
  speech_to_text: ^7.3.0       # voice commands (optional feature, off by default)
  shared_preferences: ^2.3.0   # saves the voice settings and personal bests
```

Then run `flutter pub get` and `flutter analyze`.

## 2. Android: `android/app/src/main/AndroidManifest.xml`

Inside `<manifest>`, next to the camera permission:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>

<queries>
    <intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>
    <intent><action android:name="android.speech.RecognitionService"/></intent>
</queries>
```

In `android/app/build.gradle` (or `build.gradle.kts`), set `minSdk` to at least **23**,
which headphone detection needs.

## 3. iOS: `ios/Runner/Info.plist`

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Voice commands like "finish" and "next set" while you train.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Understands voice commands like "finish" and "next set".</string>
```

## 4. Arabic voice on the phone

The coach uses the voices installed on the phone. Many phones need the Arabic voice
downloaded once:
- **Android:** Settings > Text-to-speech > Google > Install voice data > Arabic
- **iPhone:** Settings > Accessibility > Spoken Content > Voices > Arabic

The settings screen tells the user when no Arabic voice is installed, and when there is
no Egyptian (ar-EG) voice. In that case a general Arabic voice reads the Egyptian text:
the words are Egyptian, but the accent depends on the voice.

## Files

| File | What it does |
|---|---|
| `features/voice_coach/domain/entities/voice_settings.dart` | All the options: language, gender, personality, verbosity, rate, pitch, music, headphones, rep goal, commands, accessibility |
| `features/voice_coach/domain/entities/coach_cue.dart` | Every warning and setup hint as an ID with a safety priority, mapped from the rep counter's messages |
| `features/voice_coach/data/datasources/phrase_bank.dart` | **All spoken text, English and Egyptian Arabic, in one place.** Edit wording here. |
| `features/voice_coach/data/datasources/tts_engine.dart` | flutter_tts + audio focus, voice and gender picking, headphone check |
| `features/voice_coach/data/datasources/voice_command_listener.dart` | Speech recognition loop and the command words in both languages |
| `features/voice_coach/presentation/voice_coach.dart` | The logic: what to say and when (priority, cooldowns, reps, rest, summary) |
| `features/voice_coach/presentation/screens/voice_settings_screen.dart` | Settings screen with a "Test voice" button |
| `features/voice_coach/presentation/widgets/voice_language_sheet.dart` | First-launch language picker |
| `features/voice_coach/presentation/widgets/voice_quick_sheet.dart` | Speaker button on the trainer: mute, language, verbosity |

## Changes to existing files

- `injection_container.dart`: `initVoiceCoach()` (settings, engine and microphone are singletons; one coach per workout).
- `main.dart`: provides `VoiceSettingsCubit` to the whole app.
- `training_menu_screen.dart`: now a StatefulWidget. Shows the first-launch language picker and adds a voice settings button.
- `trainer_screen.dart`: creates the coach, handles voice commands (including closing the "Rest finished" dialog), adds the speaker button. When the coach speaks the 3-2-1 countdown, the click sound is skipped (the phone still vibrates).
- `rep_counter.dart`: one new public method, `isSevere(message, t)`. Nothing else changed.

## How the coach decides what to say

- **Severity:** a clear fault (one that rejects the rep) is spoken at once and can cut off less important speech. A smaller warning is spoken only if it lasts 1 second or comes back twice within 20 seconds.
- **No spam:** the same warning waits at least 7 seconds before repeating, with a 2.5 second gap between any two warnings. If the user keeps making the same mistake, the wording changes ("Remember, chest up" / "افتكر، ارفع صدرك").
- **One at a time:** if several problems show at once, only the most dangerous is spoken (spine > knees > chest > ...; see `coach_cue.dart`).
- **Stale speech is dropped:** a rep count older than about 2 seconds is not spoken late.
- **Personal bests** (reps per set, average form per set) are saved for each exercise. They are celebrated in the "Full coach" mode.

## Not included: recorded voice clips

The engine uses the phone's voices, which works offline and costs nothing. For a
consistent, natural Egyptian voice on every phone, you could later generate the fixed
lines from `phrase_bank.dart` once with a cloud voice (for example Azure `ar-EG-SalmaNeural`
/ `ar-EG-ShakirNeural`) and play those audio files instead. Numbers and summaries would
still need TTS, or one clip per number. `TtsEngine.speak()` is the single place to plug
that in.

---

# Real Egyptian voice (Shakir / Salma)

Phone voices (Majed, Laila…) speak standard Arabic and sound wrong on Egyptian words.
So every Arabic piece the coach says is recorded **once** with Microsoft Azure's Egyptian
voices and bundled in the app. It works offline, with no internet during workouts.

- `lib/features/voice_coach/data/datasources/clip_text.dart`: cuts sentences into pieces and names the clip files (shared with the tool).
- `tool/make_egyptian_voice.dart`: lists every Arabic piece (all personalities, both Arabic styles) and downloads it from Azure in both voices.
- `assets/voice/ar_eg/`: the clips (`male/`, `female/`), `manifest.json` and `pieces.txt` (which text each file says).
- The engine plays clips in a row. A piece with no clip (for example new text you added later) is read by the phone voice, so nothing is ever silent.

Packages: `flutter pub add just_audio`

pubspec.yaml, under `flutter:`:
```yaml
  assets:
    - assets/voice/ar_eg/
    - assets/voice/ar_eg/male/
    - assets/voice/ar_eg/female/
```

Make the clips (from the project folder):
```
dart run tool/make_egyptian_voice.dart --key YOUR_AZURE_KEY --region YOUR_REGION
```
On the free Azure tier this takes about 30–45 minutes (Azure allows about 20 requests a minute; the tool waits by itself).
If you change Arabic text in `phrase_bank.dart`, run it again: only the new pieces are made.
**Never put the key in the code or on GitHub.**
