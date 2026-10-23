part of 'face_detection_bloc.dart';

sealed class FaceDetectionEvent extends Equatable {
  const FaceDetectionEvent();

  @override
  List<Object> get props => [];
}

final class FaceFrameReceived extends FaceDetectionEvent {
  final CameraFrame frame;

  const FaceFrameReceived({required this.frame});

  @override
  List<Object> get props => [frame];
}
