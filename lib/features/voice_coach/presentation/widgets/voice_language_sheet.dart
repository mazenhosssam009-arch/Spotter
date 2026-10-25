import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:ai_trainer/core/theme/spotter_theme.dart';
import 'package:ai_trainer/core/widgets/spot_widgets.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/phrase_bank.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/tts_engine.dart';
import 'package:ai_trainer/features/voice_coach/domain/entities/voice_settings.dart';
import 'package:ai_trainer/features/voice_coach/presentation/cubit/voice_settings_cubit.dart';
import 'package:ai_trainer/injection_container.dart';

/// First launch: "Which language should your coach speak?" English or Egyptian Arabic,
/// plus male / female. Can be changed later in the voice settings.
Future<void> showVoiceLanguageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Sp.cardHigh,
    builder: (_) => const _LanguageSheet(),
  );
}

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet();

  Widget _option(BuildContext context, VoiceSettings s, CoachLanguage lang, String title, String sub) {
    final selected = s.language == lang;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SpotCard(
        padding: EdgeInsets.zero,
        borderColor: selected ? Sp.mint : Sp.line,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(title, style: Sp.headlineSm),
          subtitle: Text(sub, style: Sp.bodySm.copyWith(color: Sp.muted)),
          trailing: Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? Sp.mint : Sp.outline),
          onTap: () async {
            final cubit = context.read<VoiceSettingsCubit>();
            await cubit.update((x) => x.copyWith(language: lang, clearVoiceName: x.language != lang));
            await sl<TtsEngine>().speak(PhraseBank(cubit.state).sample, interrupt: true, preview: true);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VoiceSettingsCubit, VoiceSettings>(
      builder: (context, s) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Your voice coach', style: Sp.headlineMd),
            const SizedBox(height: 4),
            Text('Which language should the coach speak when it warns you or counts your reps?',
                style: Sp.bodyMd.copyWith(color: Sp.muted)),
            const SizedBox(height: 16),
            _option(context, s, CoachLanguage.english, 'English', '"Push your knees out"'),
            _option(context, s, CoachLanguage.arabicEgyptian, 'العربية (مصري)', '"زُقّ ركبك لبرّه"'),
            const SizedBox(height: 4),
            SegmentedButton<VoiceGender>(
              segments: const [
                ButtonSegment(value: VoiceGender.male, label: Text('Male voice'), icon: Icon(Icons.man)),
                ButtonSegment(value: VoiceGender.female, label: Text('Female voice'), icon: Icon(Icons.woman)),
              ],
              selected: {s.gender},
              onSelectionChanged: (v) =>
                  context.read<VoiceSettingsCubit>().update((x) => x.copyWith(gender: v.first, clearVoiceName: true)),
            ),
            const SizedBox(height: 8),
            Text('Tap a language to hear it. You can change this any time in Voice coach settings.',
                style: Sp.bodySm.copyWith(color: Sp.outline)),
            const SizedBox(height: 16),
            SpotButton('Continue', onPressed: () async {
              final cubit = context.read<VoiceSettingsCubit>();
              await cubit.chooseLanguage(cubit.state.language);
              if (context.mounted) Navigator.pop(context);
            }),
            SpotButton('No voice coach', kind: SpotKind.link, onPressed: () async {
              final cubit = context.read<VoiceSettingsCubit>();
              await cubit.update((x) => x.copyWith(languageChosen: true, verbosity: CoachVerbosity.off));
              if (context.mounted) Navigator.pop(context);
            }),
          ]),
        ),
      ),
    );
  }
}
