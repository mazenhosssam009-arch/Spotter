import 'dart:async';
import 'dart:math' as math;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_trainer/core/camera/camera_frame.dart';
import 'package:ai_trainer/core/camera/frame_throttle.dart';
import 'package:ai_trainer/core/constants.dart';
import 'package:ai_trainer/core/utils/cv_math.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/services/rep_counter.dart';
import 'package:ai_trainer/features/pose_coaching/domain/usecases/process_pose_frame_usecase.dart';

part 'trainer_event.dart';
part 'trainer_state.dart';

// the trainer screen: camera frames -> reps and form, plus sets, rest timer and
// the 3-2-1 countdown (the USER ends a set, no automatic set detection)
class TrainerBloc extends Bloc<TrainerEvent, TrainerState> {
  ProcessPoseFrameUseCase processPoseFrame;

  static const maxExtensions = 2; // the rest can be extended only 2 times
  static const readySeconds = 3;
  static const minRestSeconds = 5.0;
  static const maxRestSeconds = 600.0; // 10 minutes

  final _throttle = FrameThrottle();
  Timer? _ticker;
  double ptime = 0;
  double _lastUi = 0;
  int _lastBeepSec = -1;

  TrainerBloc({required this.processPoseFrame}) : super(const TrainerState()) {
    on<TrainerStarted>((event, emit) {
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => add(TrainerTicked()));
      emit(state.copyWith(counter: RepCounter(event.exercise, debug: debugHud), panelVersion: state.panelVersion + 1));
    });

    on<TrainerFrameReceived>((event, emit) async {
      // rest screen / get-ready: nothing is counted, tracked or drawn
      if (state.counter == null || state.paused) return;
      await _throttle.run(event.frame, (frame) async {
        final counter = state.counter!;
        if (state.paused) return;
        final res = await processPoseFrame(ProcessPoseParams(frame: frame, counter: counter));
        if (isClosed) return;
        res.fold((failure) => debugPrint('frame error: ${failure.message}'), (pose) {
          final ctime = now();
          final dtFrame = ctime - ptime;
          final fps = dtFrame > 0 ? 1 / dtFrame : 0.0;
          ptime = ctime;
          // redraw the panel under the camera (about 12 times a second is enough)
          var panel = state.panelVersion;
          if (ctime - _lastUi > 0.08) {
            _lastUi = ctime;
            panel++;
          }
          emit(state.copyWith(
            pose: pose,
            imageWidth: frame.uprightWidth,
            imageHeight: frame.uprightHeight,
            isMirrored: frame.isFrontCamera,
            fps: fps,
            frameNumber: state.frameNumber + 1,
            panelVersion: panel,
          ));
        });
      }, isClosed: () => isClosed);
    });

    on<TrainerTicked>(_onTick);

    on<ArmModeChanged>((event, emit) {
      final counter = state.counter;
      if (counter == null || !counter.setArmMode(event.armMode)) return;
      emit(state.copyWith(
        phase: WorkoutPhase.active,
        restFinished: false,
        extraUsed: 0,
        panelVersion: state.panelVersion + 1,
      ));
    });

    on<LyingCheckToggled>((event, emit) {
      state.counter?.toggleLyingCheck();
      emit(state.copyWith(panelVersion: state.panelVersion + 1));
    });

    on<RepAdjusted>((event, emit) {
      state.counter?.adjustRep(event.delta, now());
      emit(state.copyWith(panelVersion: state.panelVersion + 1));
    });

    on<SetFinished>((event, emit) {
      if ((state.counter?.setReps ?? 0) == 0) return;
      emit(_startRest(state));
    });

    on<RestStopped>((event, emit) {
      final elapsed = (_nowMs() - state.restStartMs) / 1000.0;
      state.counter?.resumeSet(elapsed);
      emit(state.copyWith(
        phase: WorkoutPhase.active,
        restFinished: false,
        panelVersion: state.panelVersion + 1,
      ));
    });

    on<NextSetStarted>((event, emit) {
      if (!state.resting) return;
      state.counter?.nextSet();
      emit(_startGetReady(state.copyWith(restFinished: false)));
    });

    on<RestExtended>((event, emit) {
      if (!state.resting) return;
      emit(_armRest(
        state.copyWith(extraUsed: state.extraUsed + 1, restFinished: false),
        (state.restSeconds * 1000).round(),
      ));
    });

    on<GetReadySkipped>((event, emit) => emit(_endGetReady(state)));

    on<RestTimeChanged>((event, emit) {
      final s = state.copyWith(restSeconds: event.seconds, panelVersion: state.panelVersion + 1);
      if (event.startRest && !s.paused && (s.counter?.setReps ?? 0) > 0) {
        emit(_startRest(s));
      } else if (!event.startRest && s.resting) {
        // Save & restart: the countdown starts again with the new time at once
        emit(_armRest(s, (event.seconds * 1000).round()));
      } else {
        emit(s);
      }
    });
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  TrainerState _armRest(TrainerState s, int ms) {
    _lastBeepSec = -1;
    return s.copyWith(restEndMs: _nowMs() + ms, restTotalMs: math.max(ms, 1));
  }

  /// starts the rest screen
  TrainerState _startRest(TrainerState s) {
    s.counter?.endSet();
    return _armRest(
      s.copyWith(
        phase: WorkoutPhase.resting,
        extraUsed: 0,
        restFinished: false,
        restStartMs: _nowMs(),
      ),
      (s.restSeconds * 1000).round(),
    );
  }

  TrainerState _startGetReady(TrainerState s) {
    _lastBeepSec = -1;
    return s.copyWith(phase: WorkoutPhase.getReady, readyEndMs: _nowMs() + readySeconds * 1000);
  }

  TrainerState _endGetReady(TrainerState s) {
    s.counter?.resetTracking();
    return s.copyWith(phase: WorkoutPhase.active, panelVersion: s.panelVersion + 1);
  }

  void _onTick(TrainerTicked event, Emitter<TrainerState> emit) {
    if (state.phase == WorkoutPhase.active) return;
    final n = _nowMs();
    if (state.resting) {
      if (state.restFinished) return;
      final left = state.restEndMs - n;
      if (left <= 0) {
        // the rest timer ran out: alert, then "Next set" or "More time" (max 2 times)
        emit(state.copyWith(restFinished: true));
        return;
      }
      final sec = (left / 1000).ceil();
      var beeps = state.beeps;
      if (sec <= 3 && sec != _lastBeepSec) {
        _lastBeepSec = sec; // short beep for the last 3 seconds
        beeps++;
      }
      emit(state.copyWith(beeps: beeps, tick: state.tick + 1));
    } else {
      final left = state.readyEndMs - n;
      if (left <= 0) {
        emit(_endGetReady(state));
        return;
      }
      final sec = (left / 1000).ceil();
      var beeps = state.beeps;
      if (sec != _lastBeepSec) {
        _lastBeepSec = sec;
        beeps++;
      }
      emit(state.copyWith(beeps: beeps, tick: state.tick + 1));
    }
  }

  @override
  Future<void> close() async {
    _ticker?.cancel();
    await processPoseFrame.dispose();
    return super.close();
  }
}
