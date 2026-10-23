import 'package:flutter/material.dart';

import 'package:ai_trainer/core/widgets/spot_widgets.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/bloc/trainer_bloc/trainer_bloc.dart';

/// what the user chose in the rest timer dialog
class RestTimerChoice {
  const RestTimerChoice(this.seconds, {this.startRest = false});
  final double seconds;
  final bool startRest; // "Start rest" instead of "Save"
}

/// Timer button (and "Edit time" on the rest screen): choose the rest time, 5 s to 10 min.
/// While the rest is running, Save restarts the countdown with the new time at once.
/// Returns null on Cancel.
Future<RestTimerChoice?> showRestTimerDialog(
  BuildContext context, {
  required double restSeconds,
  required bool resting,
}) {
  var mins = restSeconds >= 60 && restSeconds % 60 == 0;
  final ctl = TextEditingController(
      text: (mins ? restSeconds / 60 : restSeconds).round().toString());
  String? err;
  // (the controller is not disposed on purpose: the dialog is still animating out)
  return showDialog<RestTimerChoice>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) {
        void save({required bool startRest}) {
          final v = double.tryParse(ctl.text.trim().replaceAll(',', '.'));
          if (v == null || v <= 0) {
            setD(() => err = 'Enter a number');
            return;
          }
          final secs = mins ? v * 60 : v;
          if (secs < TrainerBloc.minRestSeconds) {
            setD(() => err = 'Minimum is 5 seconds');
            return;
          }
          if (secs > TrainerBloc.maxRestSeconds) {
            setD(() => err = 'Maximum is 10 minutes');
            return;
          }
          Navigator.pop(c, RestTimerChoice(secs, startRest: startRest));
        }

        return SpotDialog(
          title: resting ? 'Change rest time' : 'Rest timer',
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final q in const [30, 60, 90, 120, 180, 300])
                ActionChip(
                  label: Text(q < 60 ? '${q}s' : '${q ~/ 60}:${(q % 60).toString().padLeft(2, '0')}'),
                  onPressed: () => setD(() {
                    mins = q >= 60 && q % 60 == 0;
                    ctl.text = (mins ? q / 60 : q).round().toString();
                    err = null;
                  }),
                ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: ctl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Rest time',
                helperText: 'From 5 seconds to 10 minutes',
                errorText: err,
              ),
              onChanged: (_) => setD(() => err = null),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Seconds')),
                ButtonSegment(value: true, label: Text('Minutes')),
              ],
              selected: {mins},
              onSelectionChanged: (s) => setD(() {
                mins = s.first;
                err = null;
              }),
            ),
          ]),
          actions: [
            if (resting)
              SpotButton('Save & restart', onPressed: () => save(startRest: false))
            else ...[
              SpotButton('Start rest', icon: Icons.timer_outlined, onPressed: () => save(startRest: true)),
              SpotButton('Save', kind: SpotKind.secondary, onPressed: () => save(startRest: false)),
            ],
            SpotButton('Cancel', kind: SpotKind.link, onPressed: () => Navigator.pop(c)),
          ],
        );
      },
    ),
  );
}
