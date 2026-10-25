import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_trainer/features/voice_coach/domain/entities/voice_settings.dart';

/// saves the voice settings and the personal bests on the phone
class VoiceSettingsStore {
  VoiceSettingsStore(this._prefs);
  final SharedPreferences _prefs;

  static const _kSettings = 'voice_coach.settings';
  static const _kBestReps = 'voice_coach.best_reps.';
  static const _kBestForm = 'voice_coach.best_form.';

  VoiceSettings load() {
    final raw = _prefs.getString(_kSettings);
    if (raw == null) return const VoiceSettings();
    try {
      return VoiceSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const VoiceSettings();
    }
  }

  Future<void> save(VoiceSettings s) => _prefs.setString(_kSettings, jsonEncode(s.toJson()));

  /// most reps in one set of this exercise (0 = never done)
  int bestReps(String exercise) => _prefs.getInt('$_kBestReps$exercise') ?? 0;
  Future<void> setBestReps(String exercise, int reps) => _prefs.setInt('$_kBestReps$exercise', reps);

  /// best average form score of a set (3+ reps) of this exercise (0 = none yet)
  int bestForm(String exercise) => _prefs.getInt('$_kBestForm$exercise') ?? 0;
  Future<void> setBestForm(String exercise, int form) => _prefs.setInt('$_kBestForm$exercise', form);
}
