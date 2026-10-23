import 'package:dartz/dartz.dart';
import 'package:ai_trainer/core/camera/camera_frame.dart';
import 'package:ai_trainer/core/error/failure.dart';
import 'package:ai_trainer/features/face_detection/domain/entities/face_box.dart';

// FaceDetectionModule.FaceDetector
abstract class IFaceDetector {
  Future<Either<Failure, List<FaceBox>>> findFaces(CameraFrame frame);

  Future<void> close();
}
