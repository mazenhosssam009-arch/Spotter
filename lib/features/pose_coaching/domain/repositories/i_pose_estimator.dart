import 'package:dartz/dartz.dart';
import 'package:ai_trainer/core/error/failure.dart';
import 'package:ai_trainer/core/camera/camera_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';

// PoseModule.PoseDetector: finds the 33 body landmarks in one camera frame
abstract class IPoseEstimator {
  Future<Either<Failure, PoseFrame>> detect(CameraFrame frame);

  // pose.close()
  Future<void> close();
}
