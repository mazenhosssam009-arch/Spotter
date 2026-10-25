import 'package:bloc/bloc.dart';

import 'package:ai_trainer/features/voice_coach/data/datasources/tts_engine.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/voice_settings_store.dart';
import 'package:ai_trainer/features/voice_coach/domain/entities/voice_settings.dart';

/// the voice coach settings for the whole app (one instance, see injection_container.dart).
/// Every change is saved and applied to the voice right away.
class VoiceSettingsCubit extends Cubit<VoiceSettings> {
  VoiceSettingsCubit({required this.store, required this.engine}) : super(store.load()) {
    engine.apply(state);
  }

  final VoiceSettingsStore store;
  final TtsEngine engine;

  Future<void> update(VoiceSettings Function(VoiceSettings s) change) async {
    final next = change(state);
    if (next == state) return;
    emit(next);
    await store.save(next);
    await engine.apply(next);
  }

  /// the first-run picker / the language switch. A hand-picked voice belongs to the
  /// old language, so it is cleared.
  Future<void> chooseLanguage(CoachLanguage language) => update((s) => s.copyWith(
        language: language,
        languageChosen: true,
        clearVoiceName: s.language != language,
      ));
}
