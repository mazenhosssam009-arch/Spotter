import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:ai_trainer/core/utils/cv_math.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/bloc/trainer_bloc/trainer_bloc.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/form_colors.dart';

/// the depth bar, drawn by Flutter on top of the camera (it used to be painted pixel by
/// pixel on every camera frame). White ticks on a squat: lower = partial, upper = deep.
class DepthBar extends StatelessWidget {
  const DepthBar({super.key});

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: IgnorePointer(
          child: LayoutBuilder(
            builder: (_, c) => BlocBuilder<TrainerBloc, TrainerState>(
              buildWhen: (a, b) => a.panelVersion != b.panelVersion || a.counter != b.counter,
              builder: (context, state) {
                final counter = state.counter;
                if (counter == null) return const SizedBox.shrink();
                final e = counter.active;
                final top = c.maxHeight * 0.22, hh = c.maxHeight * 0.6;
                final col = formLevelColor(counter.formLevel(now()));
                final fill = (counter.curPer / 100).clamp(0.0, 1.0).toDouble();
                final ticks = <Widget>[];
                if (counter.isSquat) {
                  for (final a in counter.depthTickAngles) {
                    final pp = interp(a, e.downAngle, e.upAngle, 100, 0).clamp(0.0, 100.0).toDouble();
                    ticks.add(Positioned(
                        right: 12,
                        width: 24,
                        height: 2,
                        top: top + hh * (1 - pp / 100),
                        child: const ColoredBox(color: Colors.white)));
                  }
                }
                return Stack(children: [
                  Positioned(
                    right: 16,
                    width: 16,
                    top: top,
                    height: hh,
                    child: Container(
                      decoration: BoxDecoration(
                          border: Border.all(color: col, width: 2), borderRadius: BorderRadius.circular(4)),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                            heightFactor: fill, widthFactor: 1, child: ColoredBox(color: col)),
                      ),
                    ),
                  ),
                  ...ticks,
                ]);
              },
            ),
          ),
        ),
      );
}
