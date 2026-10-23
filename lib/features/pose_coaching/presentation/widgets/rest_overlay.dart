import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:ai_trainer/core/theme/spotter_theme.dart';
import 'package:ai_trainer/core/utils/cv_math.dart';
import 'package:ai_trainer/core/widgets/spot_widgets.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/bloc/trainer_bloc/trainer_bloc.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/form_colors.dart';

/// full-screen overlay: the rest screen, or the 3-2-1 "get ready" countdown
class RestOverlay extends StatelessWidget {
  const RestOverlay({super.key, required this.state, required this.onEditTime});

  final TrainerState state;
  final VoidCallback onEditTime;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TrainerBloc>();
    final c = state.counter!;
    final endMs = state.getReady ? state.readyEndMs : state.restEndMs;
    final leftMs = math.max(0, endMs - DateTime.now().millisecondsSinceEpoch);
    final leftSec = (leftMs / 1000).ceil();
    Widget body;
    if (state.getReady) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        SpotChip('Set ${c.setNumber}', dot: Sp.mint),
        const SizedBox(height: 24),
        Text('$leftSec', style: Sp.displayMetric.copyWith(fontSize: 160, height: 1, color: Sp.mint)),
        const SizedBox(height: 12),
        Text('GET IN POSITION', style: Sp.labelLg.copyWith(color: Sp.muted)),
        const SizedBox(height: 32),
        SpotButton('Skip', kind: SpotKind.link, onPressed: () => bloc.add(GetReadySkipped())),
      ]);
    } else {
      final fat = c.fatigue, sm = c.lastSmooth;
      final avgForm = c.setFormAverage;
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: SpotChip('Rest · set ${c.setNumber} done', dot: Sp.mint)),
        const SizedBox(height: 24),
        Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: (leftMs / state.restTotalMs).clamp(0.0, 1.0).toDouble(),
                  strokeWidth: 8,
                  color: Sp.mint,
                  backgroundColor: Sp.line,
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(mmss(leftSec.toDouble()), style: Sp.displayMetric.copyWith(color: Sp.white)),
                Text('REMAINING', style: Sp.labelSm.copyWith(color: Sp.muted)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: SpotMetric('Reps', '${c.lastSetReps}')),
          const SizedBox(width: 12),
          Expanded(child: SpotMetric('Time', mmss(c.lastSetSecs))),
          if (avgForm != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: SpotMetric('Form', '${avgForm.round()}%',
                  valueColor: avgForm >= 80 ? formGood : (avgForm >= 55 ? formWarn : formBad)),
            ),
          ],
        ]),
        if (sm != null || fat != null || state.extraUsed > 0) ...[
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            if (sm != null) SpotChip('Smooth ${sm.round()}', dot: Sp.mint),
            if (fat != null) SpotChip('Fatigue ${fat.round()}% ${fatigueWord(fat)}', dot: fatigueColor(fat)),
            if (state.extraUsed > 0)
              SpotChip('Extra time ${state.extraUsed}/${TrainerBloc.maxExtensions}', dot: formWarn),
          ]),
        ],
        const SizedBox(height: 24),
        SpotButton('Begin set ${c.setNumber + 1}',
            icon: Icons.play_arrow, onPressed: () => bloc.add(NextSetStarted())),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: SpotButton('Stop timer',
                  icon: Icons.stop,
                  kind: SpotKind.secondary,
                  height: 52,
                  onPressed: () => bloc.add(RestStopped()))),
          const SizedBox(width: 12),
          Expanded(
              child: SpotButton('Edit time',
                  icon: Icons.edit, kind: SpotKind.secondary, height: 52, onPressed: onEditTime)),
        ]),
      ]);
    }
    return Material(
      color: Sp.canvas,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: body),
          ),
        ),
      ),
    );
  }
}
