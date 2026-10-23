import 'package:dartz/dartz.dart';
import 'package:ai_trainer/core/camera/camera_frame.dart';
import 'package:ai_trainer/core/error/exception.dart';
import 'package:ai_trainer/core/error/exception_handler.dart';
import 'package:ai_trainer/core/error/failure.dart';
import 'package:ai_trainer/features/face_detection/data/datasources/face_detector_data_source.dart';
import 'package:ai_trainer/features/face_detection/domain/entities/face_box.dart';
import 'package:ai_trainer/features/face_detection/domain/repositories/i_face_detector.dart';

class FaceDetectorImpl implements IFaceDetector {
  FaceDetectorDataSource faceDetectorDataSource;
  FaceDetectorImpl({required this.faceDetectorDataSource});

  @override
  Future<Either<Failure, List<FaceBox>>> findFaces(CameraFrame frame) async {
    try {
      return Right(await faceDetectorDataSource.findFaces(frame));
    } on PoseException catch (e) {
      return Left(PoseFailure(message: ExceptionHandler.poseExceptionHandler(e.code)));
    }
  }

  @override
  Future<void> close() => faceDetectorDataSource.close();
}
