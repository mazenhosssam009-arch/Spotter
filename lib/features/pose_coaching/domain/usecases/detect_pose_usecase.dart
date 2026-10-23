import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:ai_trainer/core/error/failure.dart';
import 'package:ai_trainer/core/usecases/usecase.dart';
import 'package:ai_trainer/core/camera/camera_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/repositories/i_pose_estimator.dart';

class DetectPoseParams extends Equatable {
  final CameraFrame frame;

  const DetectPoseParams({required this.frame});

  @override
  List<Object?> get props => [frame];
}

// PoseModule main(): only the pose, no rep counting (Pose Estimation demo)
class DetectPoseUseCase implements UseCase<PoseFrame, DetectPoseParams> {
  IPoseEstimator poseEstimator;
  DetectPoseUseCase({required this.poseEstimator});

  @override
  Future<Either<Failure, PoseFrame>> call(DetectPoseParams params) =>
      poseEstimator.detect(params.frame);

  Future<void> dispose() => poseEstimator.close();
}
