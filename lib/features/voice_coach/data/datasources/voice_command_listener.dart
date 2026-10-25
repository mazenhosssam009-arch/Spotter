import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:ai_trainer/features/voice_coach/domain/entities/voice_settings.dart';

/// what the user can say during a workout
enum VoiceCommand { finishSet, next, skip, moreTime, stopTimer, plusRep, minusRep, mute, unmute, howMany }

/// Hands-free control: listens all the time (while the coach is not talking) and turns
/// "finish" / "خلصت", "next" / "يلا", "more time" / "وقت زيادة"... into commands.
///
/// The phone's speech recognizer stops after a few seconds of silence, so it is
/// restarted in a loop. Android plays a short sound on every restart on some phones.
class VoiceCommandListener {
  final _stt = SpeechToText();
  final _out = StreamController<VoiceCommand>.broadcast();
  bool _ready = false;
  bool _wanted = false;
  bool _paused = false;
  bool _fired = false; // one command per listening session
  int _errors = 0;
  Timer? _restart;
  String? _locale;
  CoachLanguage _language = CoachLanguage.english;

  Stream<VoiceCommand> get commands => _out.stream;
  bool get active => _wanted;

  /// asks for the microphone / speech permission once; false = denied or no recognizer
  Future<bool> ensureReady() async {
    try {
      _ready = _ready || await _stt.initialize(onStatus: _onStatus, onError: _onError);
    } catch (e) {
      debugPrint('speech init failed: $e');
      _ready = false;
    }
    return _ready;
  }

  /// starts listening; false = no microphone permission or no recognizer on this phone
  Future<bool> start(CoachLanguage language) async {
    _language = language;
    if (!await ensureReady()) return false;
    _locale = await _pickLocale(language);
    _wanted = true;
    _errors = 0;
    _listen();
    return true;
  }

  Future<String?> _pickLocale(CoachLanguage l) async {
    try {
      final all = await _stt.locales();
      String norm(String id) => id.toLowerCase().replaceAll('-', '_');
      final want = l == CoachLanguage.arabicEgyptian ? 'ar' : 'en';
      final best = l == CoachLanguage.arabicEgyptian ? 'ar_eg' : 'en_us';
      for (final x in all) {
        if (norm(x.localeId) == best) return x.localeId;
      }
      for (final x in all) {
        if (norm(x.localeId).startsWith(want)) return x.localeId;
      }
    } catch (_) {}
    return null; // the phone's default
  }

  /// the coach is talking: do not listen to ourselves
  void pause() {
    _paused = true;
    _restart?.cancel();
    if (_stt.isListening) _stt.stop();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _restartSoon(300);
  }

  Future<void> stop() async {
    _wanted = false;
    _restart?.cancel();
    try {
      await _stt.cancel();
    } catch (_) {}
  }

  void _listen() {
    if (!_wanted || _paused || !_ready || _stt.isListening) return;
    _fired = false;
    try {
      // listenFor / pauseFor / localeId are passed directly so this works on every
      // speech_to_text 7.x (the newest versions also accept them in SpeechListenOptions)
      _stt.listen(
        onResult: _onResult,
        // ignore: deprecated_member_use
        localeId: _locale,
        // ignore: deprecated_member_use
        listenFor: const Duration(seconds: 60),
        // ignore: deprecated_member_use
        pauseFor: const Duration(seconds: 5),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.confirmation,
        ),
      );
    } catch (e) {
      debugPrint('speech listen failed: $e');
      _restartSoon(2000);
    }
  }

  void _restartSoon(int ms) {
    _restart?.cancel();
    if (!_wanted || _paused) return;
    _restart = Timer(Duration(milliseconds: ms), _listen);
  }

  void _onStatus(String status) {
    if (status == 'done' || status == 'notListening') _restartSoon(400);
  }

  void _onError(SpeechRecognitionError e) {
    // "no match" / "speech timeout" are normal in a loop; back off on repeated errors
    _errors = e.errorMsg.contains('no_match') || e.errorMsg.contains('timeout') ? 0 : _errors + 1;
    if (e.errorMsg.contains('permission')) {
      _wanted = false;
      return;
    }
    _restartSoon((400 + _errors * 800).clamp(400, 5000).toInt());
  }

  void _onResult(SpeechRecognitionResult r) {
    if (_fired) return;
    final cmd = parse(r.recognizedWords, _language);
    if (cmd == null) return;
    _fired = true;
    _out.add(cmd);
    if (_stt.isListening) _stt.stop(); // start fresh for the next command
  }

  // ------------------------------------------------------------------ parsing

  /// longer / more specific phrases first ("unmute" before "mute", "stop timer" before "stop")
  static const _en = <(VoiceCommand, List<String>)>[
    (VoiceCommand.moreTime, ['more time', 'extend', 'extra time', 'more rest']),
    (VoiceCommand.stopTimer, ['stop timer', 'back to camera', 'cancel rest']),
    (VoiceCommand.plusRep, ['plus one', 'add rep', 'add one', 'add a rep']),
    (VoiceCommand.minusRep, ['minus one', 'remove rep', 'remove one', 'take one off']),
    (VoiceCommand.howMany, ['how many', 'rep count']),
    (VoiceCommand.unmute, ['unmute', 'talk to me']),
    (VoiceCommand.mute, ['mute', 'be quiet', 'quiet', 'shut up']),
    (VoiceCommand.finishSet, ['finish', 'end set', 'set done', 'done', 'stop']),
    (VoiceCommand.skip, ['skip']),
    (VoiceCommand.next, ['next', 'start', 'begin', 'ready', 'go']),
  ];

  /// Egyptian Arabic, written without diacritics and with أ/إ/آ -> ا, ة -> ه, ى -> ي
  static const _ar = <(VoiceCommand, List<String>)>[
    (VoiceCommand.moreTime, ['وقت زياده', 'كمان وقت', 'زود الوقت', 'زود وقت', 'وقت كمان', 'راحه كمان']),
    (VoiceCommand.stopTimer, ['وقف التايمر', 'وقف العداد', 'الغي الراحه', 'ارجع للكاميرا']),
    (VoiceCommand.plusRep, ['زود عده', 'زود ريب', 'زود واحده', 'زود واحد']),
    (VoiceCommand.minusRep, ['شيل عده', 'شيل ريب', 'شيل واحده', 'شيل واحد', 'نقص واحده', 'انقص']),
    (VoiceCommand.howMany, ['عديت كام', 'عملت كام', 'كام']),
    (VoiceCommand.unmute, ['اتكلم', 'كلمني', 'رجع الصوت']),
    (VoiceCommand.mute, ['اسكت', 'اقفل الصوت', 'كفايه كلام']),
    (VoiceCommand.finishSet, ['خلص السيت', 'خلص الجوله', 'خلصت', 'خلاص', 'انهي']),
    (VoiceCommand.skip, ['تخطي', 'سكيب']),
    (VoiceCommand.next, ['اللي بعده', 'التالي', 'نكست', 'ستارت', 'ابدا', 'جاهز', 'يلا']),
  ];

  static String _normAr(String t) => t
      .replaceAll(RegExp('[ً-ْـ]'), '') // diacritics + tatweel
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي');

  static VoiceCommand? _match(String text, List<(VoiceCommand, List<String>)> table, {bool words = false}) {
    for (final (cmd, phrases) in table) {
      for (final p in phrases) {
        // English: whole words only ("go" must not match "good")
        final hit = words ? RegExp('\\b${RegExp.escape(p)}\\b').hasMatch(text) : text.contains(p);
        if (hit) return cmd;
      }
    }
    return null;
  }

  /// text the recognizer heard -> command (null = nothing we know)
  static VoiceCommand? parse(String heard, CoachLanguage language) {
    final t = heard.toLowerCase().trim();
    if (t.isEmpty) return null;
    if (language == CoachLanguage.arabicEgyptian) {
      // Egyptians mix in English gym words, so the English list is checked too
      return _match(_normAr(t), _ar) ?? _match(t, _en, words: true);
    }
    return _match(t, _en, words: true);
  }

  Future<void> dispose() async {
    await stop();
    await _out.close();
  }
}
