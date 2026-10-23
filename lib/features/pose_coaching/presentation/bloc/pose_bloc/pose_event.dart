part of 'pose_bloc.dart';

sealed class PoseEvent extends Equatable {
  const PoseEvent();

  @override
  List<Object> get props => [];
}

final class PoseFrameReceived extends PoseEvent {
  final CameraFrame frame;

  const PoseFrameReceived({required this.frame});

  @override
  List<Object> get props => [frame];
}
