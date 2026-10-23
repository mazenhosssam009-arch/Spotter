part of 'trainer_bloc.dart';

// active = camera works, resting = rest screen, getReady = 3-2-1 before the next set
enum WorkoutPhase { active, resting, getReady }

class TrainerState extends Equatable {
  // rep counting, form and sets of this workout (null until TrainerStarted)
  final RepCounter? counter;
  // the last detected pose and the picture it came from
  final PoseFrame? pose;
  final double imageWidth;
  final double imageHeight;
  final bool isMirrored;
  final double fps;

  final WorkoutPhase phase;
  final int restStartMs;
  final int restEndMs;
  final int restTotalMs;
  final int readyEndMs;
  final double restSeconds; // adjustable with the timer button
  final int extraUsed; // "more time" used in this rest
  final bool restFinished; // the rest timer ran out: the "rest finished" dialog is open

  // counters that tell the screen what to redraw / play
  final int frameNumber; // camera overlay
  final int panelVersion; // panel under the camera (about 12 times a second)
  final int tick; // rest / get-ready countdown
  final int beeps; // a short beep is due

  const TrainerState({
    this.counter,
    this.pose,
    this.imageWidth = 1,
    this.imageHeight = 1,
    this.isMirrored = false,
    this.fps = 0,
    this.phase = WorkoutPhase.active,
    this.restStartMs = 0,
    this.restEndMs = 0,
    this.restTotalMs = 1,
    this.readyEndMs = 0,
    this.restSeconds = 90,
    this.extraUsed = 0,
    this.restFinished = false,
    this.frameNumber = 0,
    this.panelVersion = 0,
    this.tick = 0,
    this.beeps = 0,
  });

  bool get resting => phase == WorkoutPhase.resting;
  bool get getReady => phase == WorkoutPhase.getReady;
  // camera frames are ignored and an overlay covers the screen
  bool get paused => phase != WorkoutPhase.active;

  TrainerState copyWith({
    RepCounter? counter,
    PoseFrame? pose,
    double? imageWidth,
    double? imageHeight,
    bool? isMirrored,
    double? fps,
    WorkoutPhase? phase,
    int? restStartMs,
    int? restEndMs,
    int? restTotalMs,
    int? readyEndMs,
    double? restSeconds,
    int? extraUsed,
    bool? restFinished,
    int? frameNumber,
    int? panelVersion,
    int? tick,
    int? beeps,
  }) {
    return TrainerState(
      counter: counter ?? this.counter,
      pose: pose ?? this.pose,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      isMirrored: isMirrored ?? this.isMirrored,
      fps: fps ?? this.fps,
      phase: phase ?? this.phase,
      restStartMs: restStartMs ?? this.restStartMs,
      restEndMs: restEndMs ?? this.restEndMs,
      restTotalMs: restTotalMs ?? this.restTotalMs,
      readyEndMs: readyEndMs ?? this.readyEndMs,
      restSeconds: restSeconds ?? this.restSeconds,
      extraUsed: extraUsed ?? this.extraUsed,
      restFinished: restFinished ?? this.restFinished,
      frameNumber: frameNumber ?? this.frameNumber,
      panelVersion: panelVersion ?? this.panelVersion,
      tick: tick ?? this.tick,
      beeps: beeps ?? this.beeps,
    );
  }

  @override
  List<Object?> get props => [
    counter,
    phase,
    restStartMs,
    restEndMs,
    readyEndMs,
    restSeconds,
    extraUsed,
    restFinished,
    frameNumber,
    panelVersion,
    tick,
    beeps,
  ];
}
