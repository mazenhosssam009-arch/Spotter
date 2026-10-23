import 'package:equatable/equatable.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/body_landmark.dart';

// one detected pose (PoseModule.findPose results)
class PoseFrame extends Equatable {
  // 33 BlazePose landmarks in camera picture pixels (index = landmark id),
  // empty when nobody is seen
  final List<BodyLandmark> landmarks;
  final DateTime timestamp;

  const PoseFrame({required this.landmarks, required this.timestamp});

  const PoseFrame.empty(this.timestamp) : landmarks = const [];

  bool get hasPerson => landmarks.isNotEmpty;

  BodyLandmark landmark(int id) => landmarks[id];

  /// true when all these landmarks are really seen (like mediapipe drawing only
  /// landmarks with visibility > 0.5), not guessed because they are off screen
  bool isVisible(List<int> ids) =>
      hasPerson && ids.every((id) => landmarks[id].isVisible);

  // mp.solutions.pose.POSE_CONNECTIONS (ML Kit uses the same 33 landmark ids)
  static const List<List<int>> connections = [
    [0, 1], [1, 2], [2, 3], [3, 7], [0, 4], [4, 5], [5, 6], [6, 8], [9, 10],
    [11, 12], [11, 13], [13, 15], [15, 17], [15, 19], [15, 21], [17, 19],
    [12, 14], [14, 16], [16, 18], [16, 20], [16, 22], [18, 20], [11, 23],
    [12, 24], [23, 24], [23, 25], [24, 26], [25, 27], [26, 28], [27, 29],
    [28, 30], [29, 31], [30, 32], [27, 31], [28, 32],
  ];

  @override
  List<Object?> get props => [landmarks, timestamp];
}
