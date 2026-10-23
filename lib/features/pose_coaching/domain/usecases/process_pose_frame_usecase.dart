import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:ai_trainer/core/error/failure.dart';
import 'package:ai_trainer/core/usecases/usecase.dart';
import 'package:ai_trainer/core/utils/cv_math.dart';
import 'package:ai_trainer/core/camera/camera_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/repositories/i_pose_estimator.dart';
import 'package:ai_trainer/features/pose_coaching/domain/services/rep_counter.dart';

class ProcessPoseParams extends Equatable {
  final CameraFrame frame;
  final RepCounter counter; // the workout this frame belongs to

  const ProcessPoseParams({required this.frame, required this.counter});

  @override
  List<Object?> get props => [frame, counter];
}

// one frame of the trainer loop: find the pose, then count reps and check form
class ProcessPoseFrameUseCase implements UseCase<PoseFrame, ProcessPoseParams> {
  IPoseEstimator poseEstimator;
  ProcessPoseFrameUseCase({required this.poseEstimator});

  @override
  Future<Either<Failure, PoseFrame>> call(ProcessPoseParams params) async {
    final res = await poseEstimator.detect(params.frame);
    return res.map((pose) {
      params.counter.update(pose, now());
      return pose;
    });
  }

  Future<void> dispose() => poseEstimator.close();
}
