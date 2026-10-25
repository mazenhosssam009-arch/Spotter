import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:ai_trainer/features/voice_coach/domain/entities/voice_settings.dart';

/// one voice installed on the phone
class VoiceInfo {
  const VoiceInfo({required this.name, required this.locale, this.gender});
  final String name;
  final String locale;

  /// null = the phone does not say (we could not guess it)
  final VoiceGender? gender;

  bool get egyptian => locale.toLowerCase().replaceAll('_', '-').startsWith('ar-eg');

  /// readable label for the settings list
  String get label {
    final g = gender == null ? '' : (gender == VoiceGender.male ? ' · male' : ' · female');
    return '$name ($locale)$g';
  }
}

/// what the phone can do for the chosen language (shown in the settings)
class VoiceSupport {
  const VoiceSupport({required this.available, required this.voices, this.genderMatched = true});

  /// false = no voice for this language is installed (Arabic often needs a download)
  final bool available;
  final List<VoiceInfo> voices;

  /// false = no voice of the chosen gender: the pitch is changed instead
  final bool genderMatched;

  bool get hasEgyptian => voices.any((v) => v.egyptian);
}

/// Text to speech on the phone (flutter_tts) + audio focus for the user's music
/// (audio_session). The voices are the ones installed on the phone, so it works offline.
class TtsEngine {
  TtsEngine() {
    _tts.setStartHandler(() => speaking.value = true);
    _tts.setCompletionHandler(() => speaking.value = false);
    _tts.setCancelHandler(() => speaking.value = false);
    _tts.setErrorHandler((msg) {
      speaking.value = false;
      debugPrint('tts error: $msg');
    });
  }

  final _tts = FlutterTts();
  AudioSession? _session;
  VoiceSettings? _applied;
  List<VoiceInfo>? _voiceCache;
  bool _headphones = false;
  int _speakId = 0;
  DateTime _devicesChecked = DateTime.fromMillisecondsSinceEpoch(0);

  /// true while the coach is talking (the voice-command listener pauses meanwhile)
  final speaking = ValueNotifier<bool>(false);

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  // ------------------------------------------------------------------ voices

  Future<List<VoiceInfo>> allVoices() async {
    final cached = _voiceCache;
    if (cached != null) return cached;
    final out = <VoiceInfo>[];
    try {
      final raw = await _tts.getVoices;
      if (raw is List) {
        for (final v in raw) {
          if (v is! Map) continue;
          final name = '${v['name'] ?? ''}';
          final locale = '${v['locale'] ?? ''}';
          if (name.isEmpty || locale.isEmpty) continue;
          out.add(VoiceInfo(name: name, locale: locale, gender: _guessGender(name, v['gender'])));
        }
      }
    } catch (e) {
      debugPrint('getVoices failed: $e');
    }
    _voiceCache = out;
    return out;
  }

  /// iOS gives the gender; Android only gives a name, so known Google voice codes are used.
  /// Unknown voices stay null, and the user can pick any voice by hand in the settings.
  static VoiceGender? _guessGender(String name, Object? gender) {
    final g = '${gender ?? ''}'.toLowerCase();
    if (g.contains('female')) return VoiceGender.female;
    if (g.contains('male')) return VoiceGender.male;
    final n = name.toLowerCase();
    if (n.contains('female') || n.contains('woman')) return VoiceGender.female;
    if (n.contains('male')) return VoiceGender.male;
    // Google TTS voice codes ("en-us-x-iom-local", "ar-xa-x-ard-network")
    const female = ['-iob', '-iog', '-sfg', '-tpc', '-tpf', '-gba', '-gbc', '-gbg', '-arc', '-are'];
    const male = ['-iol', '-iom', '-tpd', '-gbb', '-gbd', '-rjs', '-ard', '-arz'];
    if (female.any(n.contains)) return VoiceGender.female;
    if (male.any(n.contains)) return VoiceGender.male;
    // common iOS / Samsung voice names
    const femaleNames = ['samantha', 'karen', 'moira', 'tessa', 'serena', 'laila', 'mariam', 'salma', 'zira', 'hoda'];
    const maleNames = ['daniel', 'alex', 'fred', 'arthur', 'aaron', 'maged', 'tarik', 'shakir', 'david', 'naayf'];
    if (femaleNames.any(n.contains)) return VoiceGender.female;
    if (maleNames.any(n.contains)) return VoiceGender.male;
    return null;
  }

  static bool _isLang(VoiceInfo v, CoachLanguage l) {
    final loc = v.locale.toLowerCase();
    return l == CoachLanguage.arabicEgyptian ? loc.startsWith('ar') : loc.startsWith('en');
  }

  Future<VoiceSupport> support(VoiceSettings s) async {
    final voices = (await allVoices()).where((v) => _isLang(v, s.language)).toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    var available = voices.isNotEmpty;
    if (!available) {
      // some engines list no voices but still speak the language
      try {
        final ok = await _tts.isLanguageAvailable(s.arabic ? 'ar' : 'en-US');
        available = ok == true || ok == 1;
      } catch (_) {}
    }
    final matched = voices.any((v) => v.gender == s.gender);
    return VoiceSupport(available: available, voices: voices, genderMatched: matched || voices.isEmpty);
  }

  /// best voice: the one picked by hand, else Egyptian Arabic / US English of the
  /// chosen gender, else any voice of the language
  VoiceInfo? _pick(List<VoiceInfo> voices, VoiceSettings s) {
    final lang = voices.where((v) => _isLang(v, s.language)).toList();
    if (lang.isEmpty) return null;
    if (s.voiceName != null) {
      for (final v in lang) {
        if (v.name == s.voiceName) return v;
      }
    }
    int score(VoiceInfo v) {
      var sc = 0;
      if (v.gender == s.gender) sc += 10;
      final loc = v.locale.toLowerCase().replaceAll('_', '-');
      if (s.arabic && v.egyptian) sc += 5;
      if (!s.arabic && loc.startsWith('en-us')) sc += 3;
      if (v.name.toLowerCase().contains('local')) sc += 1; // offline voice: no delay
      return sc;
    }

    lang.sort((a, b) => score(b) - score(a));
    return lang.first;
  }

  // ------------------------------------------------------------------ settings

  Future<void> apply(VoiceSettings s) async {
    final prev = _applied;
    _applied = s;
    try {
      await _tts.awaitSpeakCompletion(true);
      final voices = await allVoices();
      final v = _pick(voices, s);
      if (v != null) {
        await _tts.setLanguage(v.locale);
        await _tts.setVoice({'name': v.name, 'locale': v.locale});
      } else {
        await _tts.setLanguage(s.arabic ? 'ar' : 'en-US');
      }
      // the phone has no voice of the chosen gender: change the pitch instead
      var pitch = s.pitch;
      if (v == null || v.gender == null || v.gender != s.gender) {
        pitch *= s.gender == VoiceGender.male ? 0.85 : 1.12;
      }
      await _tts.setPitch(pitch.clamp(0.5, 2.0).toDouble());
      await _tts.setSpeechRate(s.rate);
      await _tts.setVolume(s.volume);
      if (prev == null || prev.musicMode != s.musicMode) await _configureAudio(s.musicMode);
    } catch (e) {
      debugPrint('tts apply failed: $e');
    }
  }

  Future<void> _configureAudio(MusicMode mode) async {
    if (_ios) {
      // iOS: the TTS audio session itself ducks / mixes / interrupts the music
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        switch (mode) {
          MusicMode.duck => [
              IosTextToSpeechAudioCategoryOptions.duckOthers,
              IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            ],
          MusicMode.mix => [IosTextToSpeechAudioCategoryOptions.mixWithOthers],
          // not mixable = other audio is interrupted while the coach talks
          MusicMode.pause => const <IosTextToSpeechAudioCategoryOptions>[],
        },
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }
    if (_android) {
      // Android: audio focus. "may duck" = music gets quieter, transient = music pauses
      final session = _session ??= await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.assistanceNavigationGuidance,
        ),
        androidAudioFocusGainType: mode == MusicMode.pause
            ? AndroidAudioFocusGainType.gainTransient
            : AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ));
    }
  }

  // ------------------------------------------------------------------ output

  /// earbuds / headphones (wired, bluetooth, USB, hearing aid) are connected
  Future<bool> headphonesConnected() async {
    if (kIsWeb) return false;
    if (DateTime.now().difference(_devicesChecked).inSeconds < 3) return _headphones;
    _devicesChecked = DateTime.now();
    try {
      final session = _session ??= await AudioSession.instance;
      final devices = await session.getDevices(includeInputs: false);
      _headphones = devices.any((d) {
        final t = d.type.name.toLowerCase();
        return t.contains('headset') ||
            t.contains('headphone') ||
            t.contains('bluetooth') ||
            t.contains('hearing') ||
            t.contains('usb') ||
            t.contains('airplay');
      });
    } catch (_) {
      _headphones = false;
    }
    return _headphones;
  }

  /// says [text]; [interrupt] = stop whatever is being said first (safety warnings);
  /// [preview] = the "Test voice" button (plays even without headphones)
  Future<void> speak(String text, {bool interrupt = false, bool preview = false}) async {
    if (text.trim().isEmpty) return;
    final s = _applied;
    if (s == null) return;
    if (!preview && s.headphonesOnly && !await headphonesConnected()) return;
    final id = ++_speakId;
    try {
      if (interrupt && speaking.value) await _tts.stop();
      final focus = _android && s.musicMode != MusicMode.mix;
      if (focus) await _session?.setActive(true);
      await _tts.speak(text); // waits until done (awaitSpeakCompletion)
      // give the music back only if nothing newer started meanwhile
      if (focus && id == _speakId) await _session?.setActive(false);
    } catch (e) {
      speaking.value = false;
      debugPrint('tts speak failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    speaking.value = false;
    if (_android) {
      try {
        await _session?.setActive(false);
      } catch (_) {}
    }
  }

  /// the voice list changes when the user installs a voice in the phone settings
  void refreshVoices() => _voiceCache = null;
}
