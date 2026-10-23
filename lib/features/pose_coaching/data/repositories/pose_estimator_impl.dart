import 'package:dartz/dartz.dart';
import 'package:ai_trainer/core/error/exception.dart';
import 'package:ai_trainer/core/error/exception_handler.dart';
import 'package:ai_trainer/core/error/failure.dart';
import 'package:ai_trainer/core/utils/cv_math.dart';
import 'package:ai_trainer/features/pose_coaching/data/datasources/landmark_smoother.dart';
import 'package:ai_trainer/features/pose_coaching/data/datasources/pose_detector_data_source.dart';
import 'package:ai_trainer/core/camera/camera_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/repositories/i_pose_estimator.dart';

// IPoseEstimator on ML Kit. Frames never leave the device and are never stored.
class PoseEstimatorImpl implements IPoseEstimator {
  PoseDetectorDataSource poseDetectorDataSource;
  LandmarkSmoother landmarkSmoother;

  PoseEstimatorImpl({
    required this.poseDetectorDataSource,
    required this.landmarkSmoother,
  });

  @override
  Future<Either<Failure, PoseFrame>> detect(CameraFrame frame) async {
    try {
      final lms = await poseDetectorDataSource.detect(frame);
      if (lms.isEmpty) {
        landmarkSmoother.reset();
        return Right(PoseFrame.empty(frame.capturedAt));
      }
      // mediapipe smooth_landmarks=True (video mode)
      return Right(PoseFrame(landmarks: landmarkSmoother.apply(lms, now()), timestamp: frame.capturedAt));
    } on PoseException catch (e) {
      return Left(PoseFailure(message: ExceptionHandler.poseExceptionHandler(e.code)));
    }
  }

  @override
  Future<void> close() => poseDetectorDataSource.close();
}
