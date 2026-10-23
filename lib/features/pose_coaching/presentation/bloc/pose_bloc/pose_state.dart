part of 'pose_bloc.dart';

sealed class PoseState extends Equatable {
  const PoseState();

  @override
  List<Object> get props => [];
}

final class PoseIdle extends PoseState {}

final class PoseActive extends PoseState {
  final PoseFrame pose;
  final double imageWidth;
  final double imageHeight;
  final bool isMirrored;
  final double fps;
  final int frameNumber;

  const PoseActive({
    required this.pose,
    required this.imageWidth,
    required this.imageHeight,
    required this.isMirrored,
    required this.fps,
    required this.frameNumber,
  });

  @override
  List<Object> get props => [frameNumber];
}
