import 'package:ai_trainer/features/voice_coach/domain/entities/voice_settings.dart';

/// one recorded Egyptian Arabic voice (a clip folder in `assets/voice/ar_eg/<id>/`).
/// Recorded once with Google Gemini text-to-speech (tool/make_egyptian_voice_gemini.py).
class EgyptianVoice {
  const EgyptianVoice(this.id, this.name, this.gender, {this.isDefault = false});

  /// clip folder name
  final String id;

  /// shown in the settings
  final String name;
  final VoiceGender gender;

  /// the voice used for this gender when the user did not pick one
  final bool isDefault;

  /// Puck and Zephyr are the defaults: they sounded the most like a normal Egyptian.
  static const all = [
    EgyptianVoice('puck', 'Puck', VoiceGender.male, isDefault: true),
    EgyptianVoice('fenrir', 'Fenrir', VoiceGender.male),
    EgyptianVoice('orus', 'Orus', VoiceGender.male),
    EgyptianVoice('zephyr', 'Zephyr', VoiceGender.female, isDefault: true),
    EgyptianVoice('kore', 'Kore', VoiceGender.female),
    EgyptianVoice('leda', 'Leda', VoiceGender.female),
  ];

  static EgyptianVoice defaultFor(VoiceGender g) => all.firstWhere((v) => v.gender == g && v.isDefault);

  static EgyptianVoice? byId(String? id) {
    for (final v in all) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// the older recording (Microsoft Shakir / Salma), used until the voices above are recorded
  static String legacyFolder(VoiceGender g) => g == VoiceGender.male ? 'male' : 'female';
}
