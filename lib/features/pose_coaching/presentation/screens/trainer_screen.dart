import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:ai_trainer/core/theme/spotter_theme.dart';
import 'package:ai_trainer/core/utils/cv_math.dart';
import 'package:ai_trainer/core/widgets/camera_view.dart';
import 'package:ai_trainer/core/widgets/overlay_canvas.dart';
import 'package:ai_trainer/core/widgets/spot_widgets.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';
import 'package:ai_trainer/features/pose_coaching/domain/services/rep_counter.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/bloc/trainer_bloc/trainer_bloc.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/depth_bar.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/exercise_guide.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/form_colors.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/rest_overlay.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/rest_timer_dialog.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/trainer_overlay.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/trainer_panel.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/voice_command_listener.dart';
import 'package:ai_trainer/features/voice_coach/presentation/voice_coach.dart';
import 'package:ai_trainer/features/voice_coach/presentation/widgets/voice_quick_sheet.dart';
import 'package:ai_trainer/injection_container.dart';

/// AiTrainer.py / SquatTrainer.py / DeadliftTrainer.py / BenchPressTrainer.py
class TrainerScreen extends StatelessWidget {
  const TrainerScreen({super.key, required this.exercise});
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<TrainerBloc>()..add(TrainerStarted(exercise: exercise)),
      child: _TrainerView(exercise: exercise),
    );
  }
}

class _TrainerView extends StatefulWidget {
  const _TrainerView({required this.exercise});
  final Exercise exercise;

  @override
  State<_TrainerView> createState() => _TrainerViewState();
}

class _TrainerViewState extends State<_TrainerView> with WidgetsBindingObserver {
  TrainerBloc get _bloc => context.read<TrainerBloc>();

  // the voice coach of this workout (form warnings, reps, rest...) and its voice commands
  late final VoiceCoach _coach;
  StreamSubscription<VoiceCommand>? _commandSub;
  BuildContext? _restDialog; // the "Rest finished" dialog while it is open

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable(); // the screen stays on during the whole workout
    _coach = sl<VoiceCoach>()..attach(_bloc, widget.exercise);
    _commandSub = _coach.commands.listen(_onVoiceCommand);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _commandSub?.cancel();
    _coach.dispose();
    super.dispose();
  }

  /// hands-free: "finish" / "خلصت", "next" / "يلا", "more time" / "وقت زيادة"...
  void _onVoiceCommand(VoiceCommand cmd) {
    if (!mounted) return;
    final s = _bloc.state;
    final dialog = _restDialog;
    switch (cmd) {
      case VoiceCommand.finishSet:
        if (!s.paused) _finishSet();
      case VoiceCommand.next:
      case VoiceCommand.skip:
        if (dialog != null) {
          Navigator.pop(dialog, false); // "Next set"
        } else if (s.getReady) {
          _bloc.add(GetReadySkipped());
        } else if (s.resting) {
          _bloc.add(NextSetStarted());
        }
      case VoiceCommand.moreTime:
        if (dialog != null && s.extraUsed < TrainerBloc.maxExtensions) Navigator.pop(dialog, true);
      case VoiceCommand.stopTimer:
        if (s.resting && !s.restFinished) _bloc.add(RestStopped());
      case VoiceCommand.plusRep:
        if (!s.paused) _bloc.add(const RepAdjusted(delta: 1));
      case VoiceCommand.minusRep:
        if (!s.paused) _bloc.add(const RepAdjusted(delta: -1));
      case VoiceCommand.mute:
      case VoiceCommand.unmute:
      case VoiceCommand.howMany:
        break; // the coach answers these itself
    }
  }

  /// timers use the wall clock, so after a phone call / background trip they are still right
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _bloc.add(TrainerTicked());
  }

  void _beep(TrainerState state) {
    // the voice coach says "3, 2, 1" itself: only vibrate then
    if (!(state.getReady && _coach.speaksCountdown)) SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
  }

  /// the rest is over: three long vibrations + system alert sound
  Future<void> _ringAlert() async {
    for (var i = 0; i < 3; i++) {
      // the voice coach announces it: one alert sound is enough, so they don't overlap
      if (i == 0 || !_coach.speaksCountdown) SystemSound.play(SystemSoundType.alert);
      HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
    }
  }

  void _needARep() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Do at least one counted rep first')));
  }

  /// Finish button: ends the set and opens the rest screen
  void _finishSet() {
    if ((_bloc.state.counter?.setReps ?? 0) == 0) {
      _needARep();
      return;
    }
    _bloc.add(SetFinished());
  }

  Future<void> _restSettings() async {
    final s = _bloc.state;
    final res = await showRestTimerDialog(context, restSeconds: s.restSeconds, resting: s.resting);
    if (!mounted || res == null) return;
    final now = _bloc.state;
    if (res.startRest && !now.paused && (now.counter?.setReps ?? 0) == 0) {
      _bloc.add(RestTimeChanged(seconds: res.seconds));
      _needARep();
      return;
    }
    _bloc.add(RestTimeChanged(seconds: res.seconds, startRest: res.startRest));
  }

  /// the rest timer ran out: alert, then "Next set" or "More time" (max 2 times)
  Future<void> _restDone(TrainerState state) async {
    _ringAlert();
    final setNumber = state.counter!.setNumber;
    final left = TrainerBloc.maxExtensions - state.extraUsed;
    final more = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        _restDialog = c;
        return PopScope(
          canPop: false,
          child: SpotDialog(
            title: 'Rest finished',
            content: Text(left > 0
                ? 'Ready for set ${setNumber + 1}? You can add more time ($left left).'
                : 'Ready for set ${setNumber + 1}? No more extra time.'),
            actions: [
              SpotButton('Next set ${setNumber + 1}',
                  icon: Icons.play_arrow, onPressed: () => Navigator.pop(c, false)),
              if (left > 0)
                SpotButton('More time +${mmss(state.restSeconds)} · $left left',
                    icon: Icons.add, kind: SpotKind.secondary, onPressed: () => Navigator.pop(c, true)),
            ],
          ),
        );
      },
    );
    _restDialog = null;
    if (!mounted) return;
    _bloc.add(more == true ? RestExtended() : NextSetStarted());
  }

  /// back button: ask first, so a workout is not lost by accident
  Future<void> _onBack() async {
    final s = _bloc.state;
    final count = s.counter?.count ?? 0;
    if (count == 0 && !s.paused) {
      Navigator.of(context).pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => SpotDialog(
        title: 'Leave the workout?',
        content: Text('Your ${count.toInt()} reps are not saved and will be lost.'),
        actions: [
          SpotButton('Stay', onPressed: () => Navigator.pop(c, false)),
          SpotButton('Leave', kind: SpotKind.destructive, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  /// top bar button: dark fill + mint border + mint icon/label, visible on any background
  Widget _pill(IconData icon, String label, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: Sp.card,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Sp.rChip), side: const BorderSide(color: Sp.mint)),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(Sp.rChip),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 18, color: Sp.mint),
                  if (label.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(label.toUpperCase(), style: Sp.labelMd.copyWith(color: Sp.mint)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      );

  /// app bar buttons; each one redraws itself when the bloc changes
  List<Widget> _actions() {
    Widget watch(Widget Function(RepCounter c) build) => BlocBuilder<TrainerBloc, TrainerState>(
          buildWhen: (a, b) => a.panelVersion != b.panelVersion || a.counter != b.counter,
          builder: (context, state) =>
              state.counter == null ? const SizedBox.shrink() : build(state.counter!),
        );
    return [
      // voice coach: tap = mute / language / settings
      ValueListenableBuilder<bool>(
        valueListenable: _coach.muted,
        builder: (context, muted, _) => _pill(
          muted ? Icons.volume_off_outlined : Icons.record_voice_over_outlined,
          '',
          'Voice coach',
          () => showVoiceQuickSheet(context, _coach),
        ),
      ),
      _pill(Icons.timer_outlined, 'Timer', 'Rest timer', _restSettings),
      _pill(Icons.school_outlined, '', 'How to do this exercise', () => showExerciseGuide(context, widget.exercise)),
      if (widget.exercise.name.contains('Bench'))
        watch((c) => IconButton(
              tooltip: c.lyingCheck ? 'Lying check ON (tap to turn off)' : 'Lying check OFF',
              icon: Icon(c.lyingCheck ? Icons.bed : Icons.bed_outlined),
              color: c.lyingCheck ? Sp.mint : Sp.outline,
              onPressed: () => _bloc.add(LyingCheckToggled()),
            )),
      if (widget.exercise.name.contains('Curl'))
        watch((c) => PopupMenuButton<int>(
          tooltip: 'Arms',
          initialValue: c.armMode,
          onSelected: (m) => _bloc.add(ArmModeChanged(armMode: m)),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 0, child: Text('Right arm')),
            PopupMenuItem(value: 1, child: Text('Left arm')),
            PopupMenuItem(value: 2, child: Text('Both arms')),
            PopupMenuItem(value: 3, child: Text('Alternate: right, left, right...')),
            PopupMenuItem(value: 4, child: Text('Alternate: left, right, left...')),
          ],
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            decoration: BoxDecoration(
              color: Sp.card,
              borderRadius: BorderRadius.circular(Sp.rChip),
              border: Border.all(color: Sp.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(armShort[c.armMode].toUpperCase(), style: Sp.labelMd.copyWith(color: Sp.white)),
              const Icon(Icons.arrow_drop_down, size: 20),
            ]),
          ),
        )),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<TrainerBloc, TrainerState>(
          listenWhen: (a, b) => a.beeps != b.beeps,
          listener: (_, state) => _beep(state),
        ),
        BlocListener<TrainerBloc, TrainerState>(
          listenWhen: (a, b) => !a.restFinished && b.restFinished,
          listener: (_, state) => _restDone(state),
        ),
      ],
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _onBack();
        },
        child: Material(
          color: Sp.canvas,
          child: Stack(children: [
            Positioned.fill(
              child: Column(children: [
                Expanded(
                  child: Stack(fit: StackFit.expand, children: [
                    CameraView(
                      title: widget.exercise.name,
                      onFrame: (frame) => _bloc.add(TrainerFrameReceived(frame: frame)),
                      actions: _actions(),
                      overlay: BlocBuilder<TrainerBloc, TrainerState>(
                        buildWhen: (a, b) => a.frameNumber != b.frameNumber || a.phase != b.phase,
                        builder: (context, state) => CustomPaint(painter: OverlayPainter(trainerOverlay(state))),
                      ),
                    ),
                    const DepthBar(),
                  ]),
                ),
                TrainerPanel(onFinishSet: _finishSet),
              ]),
            ),
            // rest screen / 3-2-1 countdown on top of everything
            Positioned.fill(
              child: BlocBuilder<TrainerBloc, TrainerState>(
                buildWhen: (a, b) => a.phase != b.phase || a.tick != b.tick || a.extraUsed != b.extraUsed,
                builder: (context, state) => state.paused && state.counter != null
                    ? RestOverlay(state: state, onEditTime: _restSettings)
                    : const SizedBox.shrink(),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
