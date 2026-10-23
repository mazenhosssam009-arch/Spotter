part of 'face_detection_bloc.dart';

sealed class FaceDetectionState extends Equatable {
  const FaceDetectionState();

  @override
  List<Object> get props => [];
}

final class FaceDetectionIdle extends FaceDetectionState {}

final class FaceDetectionActive extends FaceDetectionState {
  final List<FaceBox> faces;
  final double imageWidth;
  final double imageHeight;
  final bool isMirrored;
  final double fps;
  final int frameNumber;

  const FaceDetectionActive({
    required this.faces,
    required this.imageWidth,
    required this.imageHeight,
    required this.isMirrored,
    required this.fps,
    required this.frameNumber,
  });

  @override
  List<Object> get props => [frameNumber];
}
