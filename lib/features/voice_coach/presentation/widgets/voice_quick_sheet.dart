import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:ai_trainer/core/route/routing.dart';
import 'package:ai_trainer/core/theme/spotter_theme.dart';
import 'package:ai_trainer/features/voice_coach/domain/entities/voice_settings.dart';
import 'package:ai_trainer/features/voice_coach/presentation/cubit/voice_settings_cubit.dart';
import 'package:ai_trainer/features/voice_coach/presentation/screens/voice_settings_screen.dart';
import 'package:ai_trainer/features/voice_coach/presentation/voice_coach.dart';

/// the speaker button on the trainer screen: mute, language and how much it talks,
/// without leaving the workout
Future<void> showVoiceQuickSheet(BuildContext context, VoiceCoach coach) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Sp.cardHigh,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: BlocBuilder<VoiceSettingsCubit, VoiceSettings>(
        builder: (ctx, s) {
          final cubit = ctx.read<VoiceSettingsCubit>();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Voice coach', style: Sp.headlineSm),
              const SizedBox(height: 12),
              ValueListenableBuilder<bool>(
                valueListenable: coach.muted,
                builder: (_, muted, _) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mute for this workout'),
                  value: muted,
                  onChanged: (_) => coach.toggleMute(),
                ),
              ),
              const SizedBox(height: 4),
              SegmentedButton<CoachLanguage>(
                segments: const [
                  ButtonSegment(value: CoachLanguage.english, label: Text('English')),
                  ButtonSegment(value: CoachLanguage.arabicEgyptian, label: Text('عربي مصري')),
                ],
                selected: {s.language},
                onSelectionChanged: (v) => cubit.chooseLanguage(v.first),
              ),
              const SizedBox(height: 12),
              SegmentedButton<CoachVerbosity>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: CoachVerbosity.off, label: Text('Off')),
                  ButtonSegment(value: CoachVerbosity.warnings, label: Text('Warnings')),
                  ButtonSegment(value: CoachVerbosity.warningsReps, label: Text('+ Reps')),
                  ButtonSegment(value: CoachVerbosity.full, label: Text('Full')),
                ],
                selected: {s.verbosity},
                onSelectionChanged: (v) => cubit.update((x) => x.copyWith(verbosity: v.first)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.tune),
                label: const Text('All voice settings'),
                onPressed: () {
                  Navigator.pop(sheet);
                  // the trainer screen's context: the sheet's one is gone after pop
                  Routing.routePush(const VoiceSettingsScreen(), context);
                },
              ),
            ]),
          );
        },
      ),
    ),
  );
}
