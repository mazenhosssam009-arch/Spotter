import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:ai_trainer/core/theme/spotter_theme.dart';
import 'package:ai_trainer/core/utils/cv_math.dart';
import 'package:ai_trainer/core/widgets/spot_widgets.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/bloc/trainer_bloc/trainer_bloc.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/form_colors.dart';

/// the panel under the camera: slim by default (bigger camera), the arrow opens the full one
/// (status chips, feedback card, REPS DONE card with depth progress, FORM SCORE ring,
/// +/- rep buttons and the FINISH SET button)
class TrainerPanel extends StatefulWidget {
  const TrainerPanel({super.key, required this.onFinishSet});

  final VoidCallback onFinishSet;

  @override
  State<TrainerPanel> createState() => _TrainerPanelState();
}

class _TrainerPanelState extends State<TrainerPanel> {
  bool _expanded = false; // false = slim panel (bigger camera), true = full panel

  Widget _squareBtn(IconData icon, String tip, VoidCallback onTap) => SizedBox(
        width: 56,
        height: 56,
        child: Tooltip(
          message: tip,
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(56, 56)),
            child: Icon(icon, size: 24),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Sp.canvas,
          border: Border(top: BorderSide(color: Sp.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: SizedBox(
                  height: 22,
                  width: double.infinity,
                  child: Icon(_expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                      color: Sp.muted),
                ),
              ),
              BlocBuilder<TrainerBloc, TrainerState>(
                buildWhen: (a, b) => a.panelVersion != b.panelVersion || a.counter != b.counter,
                builder: (context, state) => state.counter == null
                    ? const SizedBox.shrink()
                    : (_expanded ? _fullPanel(context, state) : _compactPanel(state)),
              ),
            ]),
          ),
        ),
      );

  /// slim panel: reps, form ring, feedback text, finish button (one row, 56 px)
  Widget _compactPanel(TrainerState state) {
    final c = state.counter!;
    final t = now();
    final msg = c.feedback(t);
    final fc = formLevelColor(c.formLevel(t));
    return SizedBox(
      height: 56,
      child: Row(children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('REPS', style: Sp.labelSm.copyWith(color: Sp.muted)),
          Text('${c.count.toInt()}', style: Sp.displayMetric.copyWith(fontSize: 30, height: 1, color: Sp.white)),
        ]),
        const SizedBox(width: 12),
        SizedBox(
          width: 44,
          height: 44,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: c.formReady ? (c.formScore / 100).clamp(0.0, 1.0).toDouble() : 0.0,
                strokeWidth: 4,
                color: fc,
                backgroundColor: Sp.line,
              ),
            ),
            Text(c.formReady ? '${c.formScore.round()}' : '--', style: Sp.labelMd.copyWith(color: Sp.white)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(children: [
            Icon(feedbackIcon(msg.icon), color: feedbackColor(msg.tone), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Sp.headlineSm.copyWith(fontSize: 14, color: Sp.white)),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Finish set',
          child: SizedBox(
            width: 56,
            height: 56,
            child: FilledButton(
              onPressed: widget.onFinishSet,
              style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(56, 56)),
              child: const Icon(Icons.flag_outlined),
            ),
          ),
        ),
      ]),
    );
  }

  /// full panel (arrow up): chips, feedback card, reps + form score, +/- and finish
  Widget _fullPanel(BuildContext context, TrainerState state) {
    final c = state.counter!;
    final t = now();
    final msg = c.feedback(t);
    final msgColor = feedbackColor(msg.tone);
    final fc = formLevelColor(c.formLevel(t));
    final fat = c.fatigue, sm = c.lastSmooth;
    final bloc = context.read<TrainerBloc>();

    final chips = <Widget>[
      if (c.inSet)
        SpotChip('Set ${c.setNumber} · ${c.setReps} reps · ${mmss(t - c.setStart)}', dot: Sp.mint)
      else
        SpotChip('Set ${c.setNumber} · start lifting', dot: formNA),
      if (c.isCurl)
        SpotChip(
            c.altMode ? 'Next ${c.altRightNext ? 'R' : 'L'} · R ${c.repsR} · L ${c.repsL}' : armNames[c.armMode],
            dot: c.altMode ? formWarn : Sp.mint),
      if (c.isSquat) SpotChip('Partial ${c.partialReps} · Deep ${c.deepReps} · Extra ${c.extraReps}', dot: Sp.mint),
      if (sm != null) SpotChip('Smooth ${sm.round()}', dot: Sp.mint),
      if (c.inSet && fat != null) SpotChip('Fatigue ${fat.round()}% ${fatigueWord(fat)}', dot: fatigueColor(fat)),
    ];

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // status chips
      SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => Center(child: chips[i]),
        ),
      ),
      const SizedBox(height: 8),
      // feedback card
      SizedBox(
        height: 64,
        child: SpotCard(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: Sp.cardHigh, shape: BoxShape.circle),
              child: Icon(feedbackIcon(msg.icon), color: msgColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(msg.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Sp.headlineSm.copyWith(fontSize: 16, color: Sp.white)),
                if (msg.sub != null)
                  Text(msg.sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Sp.bodySm.copyWith(color: Sp.muted)),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      // reps + form score
      SizedBox(
        height: 100,
        child: Row(children: [
          Expanded(
            flex: 5,
            child: SpotCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('REPS DONE', style: Sp.labelSm.copyWith(color: Sp.muted)),
                Text('${c.count.toInt()}', style: Sp.displayMetric.copyWith(fontSize: 44, height: 1, color: Sp.white)),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (c.curPer / 100).clamp(0.0, 1.0).toDouble(),
                    minHeight: 4,
                    color: fc,
                    backgroundColor: Sp.line,
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: SpotCard(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: c.formReady ? (c.formScore / 100).clamp(0.0, 1.0).toDouble() : 0.0,
                        strokeWidth: 5,
                        color: fc,
                        backgroundColor: Sp.line,
                      ),
                    ),
                    Text(c.formReady ? '${c.formScore.round()}' : '--',
                        style: Sp.headlineSm.copyWith(color: Sp.white)),
                  ]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('FORM SCORE', maxLines: 1, style: Sp.labelSm.copyWith(color: Sp.muted, fontSize: 9)),
                    const SizedBox(height: 2),
                    Text(c.formWord, maxLines: 2, style: Sp.labelMd.copyWith(color: fc)),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      // fix a rep + finish the set
      Row(children: [
        _squareBtn(Icons.remove, 'Remove a rep', () => bloc.add(const RepAdjusted(delta: -1))),
        const SizedBox(width: 8),
        _squareBtn(Icons.add, 'Add a rep', () => bloc.add(const RepAdjusted(delta: 1))),
        const SizedBox(width: 8),
        Expanded(
          child: SpotButton(c.setReps > 0 ? 'Finish set · ${c.setReps} reps' : 'Finish set',
              icon: Icons.flag_outlined, onPressed: widget.onFinishSet),
        ),
      ]),
    ]);
  }
}
