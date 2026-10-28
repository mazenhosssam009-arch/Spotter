import 'package:equatable/equatable.dart';

/// the language the coach speaks
enum CoachLanguage { english, arabicEgyptian }

/// male / female voice (the phone's voices decide what is really available)
enum VoiceGender { female, male }

/// how the coach talks
/// calm = gentle reminders, hype = loud and motivating,
/// strict = drill sergeant, minimal = short cues only
enum CoachPersonality { calm, hype, strict, minimal }

/// how much the coach talks
/// off = silent, warnings = form warnings + setup only,
/// warningsReps = + rep counts, rep results, rest over and 3-2-1,
/// full = + praise, encouragement, rest countdown, set summary, tips, celebrations
enum CoachVerbosity { off, warnings, warningsReps, full }

/// which reps are counted out loud
/// everyRep = 1, 2, 3...; milestones = every 5th rep; nearGoal = only the last 3 before
/// the rep goal (every rep when no goal is set)
enum CountStyle { everyRep, milestones, nearGoal }

/// what happens to the user's music while the coach speaks
/// duck = music gets quieter, pause = music pauses, mix = music is not touched
enum MusicMode { duck, pause, mix }

/// Arabic only: plain Egyptian ("كمان عدتين") or gym talk with the English
/// words Egyptians use in the gym ("كمان اتنين ريبس")
enum ArabicStyle { gymSlang, plain }

class VoiceSettings extends Equatable {
  const VoiceSettings({
    this.languageChosen = false,
    this.language = CoachLanguage.english,
    this.gender = VoiceGender.male,
    this.voiceName,
    this.personality = CoachPersonality.calm,
    this.verbosity = CoachVerbosity.warningsReps,
    this.countStyle = CountStyle.everyRep,
    this.rate = 0.5,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.musicMode = MusicMode.duck,
    this.headphonesOnly = false,
    this.arabicStyle = ArabicStyle.gymSlang,
    this.repGoal = 0,
    this.voiceCommands = false,
    this.accessibility = false,
    this.egyptianClips = true,
    this.egyptianVoice,
  });

  /// false until the user picked a language once (the first-run picker)
  final bool languageChosen;
  final CoachLanguage language;
  final VoiceGender gender;

  /// a specific voice picked in the settings (null = best match for language + gender)
  final String? voiceName;
  final CoachPersonality personality;
  final CoachVerbosity verbosity;
  final CountStyle countStyle;

  /// 0..1, 0.5 = normal speed (flutter_tts scale on Android and iOS)
  final double rate;

  /// 0.5..2.0, 1.0 = normal
  final double pitch;
  final double volume;
  final MusicMode musicMode;

  /// speak only while earbuds / headphones are connected (for a quiet gym)
  final bool headphonesOnly;
  final ArabicStyle arabicStyle;

  /// target reps per set, 0 = no goal ("two more!", "last one!")
  final int repGoal;

  /// listen for "finish", "next", "more time"... (uses the microphone)
  final bool voiceCommands;

  /// low-vision mode: the coach also reads the camera setup, form score and dialogs
  final bool accessibility;

  /// Arabic: use the recorded Egyptian voices (Shakir / Salma) when the clip pack is in
  /// the app (tool/make_egyptian_voice.dart). false = the phone's Arabic voice
  final bool egyptianClips;

  /// Arabic: which recorded Egyptian voice (EgyptianVoice.id, e.g. 'puck').
  /// null = the default voice of [gender] (Puck / Zephyr). Cleared when the gender changes.
  final String? egyptianVoice;

  bool get enabled => verbosity != CoachVerbosity.off;
  bool get arabic => language == CoachLanguage.arabicEgyptian;

  VoiceSettings copyWith({
    bool? languageChosen,
    CoachLanguage? language,
    VoiceGender? gender,
    String? voiceName,
    bool clearVoiceName = false,
    CoachPersonality? personality,
    CoachVerbosity? verbosity,
    CountStyle? countStyle,
    double? rate,
    double? pitch,
    double? volume,
    MusicMode? musicMode,
    bool? headphonesOnly,
    ArabicStyle? arabicStyle,
    int? repGoal,
    bool? voiceCommands,
    bool? accessibility,
    bool? egyptianClips,
    String? egyptianVoice,
    bool clearEgyptianVoice = false,
  }) {
    // a voice of the other gender makes no sense: changing the gender goes back to its default
    final genderChanged = gender != null && gender != this.gender;
    return VoiceSettings(
      languageChosen: languageChosen ?? this.languageChosen,
      language: language ?? this.language,
      gender: gender ?? this.gender,
      voiceName: clearVoiceName ? null : (voiceName ?? this.voiceName),
      personality: personality ?? this.personality,
      verbosity: verbosity ?? this.verbosity,
      countStyle: countStyle ?? this.countStyle,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      musicMode: musicMode ?? this.musicMode,
      headphonesOnly: headphonesOnly ?? this.headphonesOnly,
      arabicStyle: arabicStyle ?? this.arabicStyle,
      repGoal: repGoal ?? this.repGoal,
      voiceCommands: voiceCommands ?? this.voiceCommands,
      accessibility: accessibility ?? this.accessibility,
      egyptianClips: egyptianClips ?? this.egyptianClips,
      egyptianVoice: clearEgyptianVoice ? null : (egyptianVoice ?? (genderChanged ? null : this.egyptianVoice)),
    );
  }

  Map<String, Object?> toJson() => {
        'languageChosen': languageChosen,
        'language': language.name,
        'gender': gender.name,
        'voiceName': voiceName,
        'personality': personality.name,
        'verbosity': verbosity.name,
        'countStyle': countStyle.name,
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
        'musicMode': musicMode.name,
        'headphonesOnly': headphonesOnly,
        'arabicStyle': arabicStyle.name,
        'repGoal': repGoal,
        'voiceCommands': voiceCommands,
        'accessibility': accessibility,
        'egyptianClips': egyptianClips,
        'egyptianVoice': egyptianVoice,
      };

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  static double _num(Object? v, double fallback) => v is num ? v.toDouble() : fallback;

  factory VoiceSettings.fromJson(Map<String, dynamic> j) {
    const d = VoiceSettings();
    return VoiceSettings(
      languageChosen: j['languageChosen'] == true,
      language: _enum(CoachLanguage.values, j['language'], d.language),
      gender: _enum(VoiceGender.values, j['gender'], d.gender),
      voiceName: j['voiceName'] is String ? j['voiceName'] as String : null,
      personality: _enum(CoachPersonality.values, j['personality'], d.personality),
      verbosity: _enum(CoachVerbosity.values, j['verbosity'], d.verbosity),
      countStyle: _enum(CountStyle.values, j['countStyle'], d.countStyle),
      rate: _num(j['rate'], d.rate).clamp(0.2, 0.9).toDouble(),
      pitch: _num(j['pitch'], d.pitch).clamp(0.5, 2.0).toDouble(),
      volume: _num(j['volume'], d.volume).clamp(0.0, 1.0).toDouble(),
      musicMode: _enum(MusicMode.values, j['musicMode'], d.musicMode),
      headphonesOnly: j['headphonesOnly'] == true,
      arabicStyle: _enum(ArabicStyle.values, j['arabicStyle'], d.arabicStyle),
      repGoal: j['repGoal'] is num ? (j['repGoal'] as num).toInt().clamp(0, 50) : 0,
      voiceCommands: j['voiceCommands'] == true,
      accessibility: j['accessibility'] == true,
      egyptianClips: j['egyptianClips'] != false,
      egyptianVoice: j['egyptianVoice'] is String ? j['egyptianVoice'] as String : null,
    );
  }

  @override
  List<Object?> get props => [
        languageChosen,
        language,
        gender,
        voiceName,
        personality,
        verbosity,
        countStyle,
        rate,
        pitch,
        volume,
        musicMode,
        headphonesOnly,
        arabicStyle,
        repGoal,
        voiceCommands,
        accessibility,
        egyptianClips,
        egyptianVoice,
      ];
}
