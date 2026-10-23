part of 'trainer_bloc.dart';

sealed class TrainerEvent extends Equatable {
  const TrainerEvent();

  @override
  List<Object> get props => [];
}

final class TrainerStarted extends TrainerEvent {
  final Exercise exercise;

  const TrainerStarted({required this.exercise});

  @override
  List<Object> get props => [exercise.name];
}

final class TrainerFrameReceived extends TrainerEvent {
  final CameraFrame frame;

  const TrainerFrameReceived({required this.frame});

  @override
  List<Object> get props => [frame];
}

/// timers use the wall clock, so after a phone call / background trip they are still right
final class TrainerTicked extends TrainerEvent {}

/// biceps curl: 0 right, 1 left, 2 both, 3 alternate R>L, 4 alternate L>R
final class ArmModeChanged extends TrainerEvent {
  final int armMode;

  const ArmModeChanged({required this.armMode});

  @override
  List<Object> get props => [armMode];
}

/// bench press: the bed button
final class LyingCheckToggled extends TrainerEvent {}

/// +1 / -1 buttons: fix a rep the camera missed or added
final class RepAdjusted extends TrainerEvent {
  final int delta;

  const RepAdjusted({required this.delta});

  @override
  List<Object> get props => [delta];
}

/// Finish set: ends the set and opens the rest screen
final class SetFinished extends TrainerEvent {}

/// Stop timer: back to the camera, still in the same set
final class RestStopped extends TrainerEvent {}

/// Begin set / Next set: new set, then the 3-2-1 countdown
final class NextSetStarted extends TrainerEvent {}

/// "More time" after the rest ran out (max 2 times)
final class RestExtended extends TrainerEvent {}

/// Skip on the 3-2-1 countdown
final class GetReadySkipped extends TrainerEvent {}

/// new rest time; [startRest] = "Start rest" in the timer dialog
final class RestTimeChanged extends TrainerEvent {
  final double seconds;
  final bool startRest;

  const RestTimeChanged({required this.seconds, this.startRest = false});

  @override
  List<Object> get props => [seconds, startRest];
}
