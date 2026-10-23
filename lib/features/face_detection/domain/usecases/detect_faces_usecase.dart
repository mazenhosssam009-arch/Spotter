import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:ai_trainer/core/camera/camera_frame.dart';
import 'package:ai_trainer/core/error/failure.dart';
import 'package:ai_trainer/core/usecases/usecase.dart';
import 'package:ai_trainer/features/face_detection/domain/entities/face_box.dart';
import 'package:ai_trainer/features/face_detection/domain/repositories/i_face_detector.dart';

class DetectFacesParams extends Equatable {
  final CameraFrame frame;

  const DetectFacesParams({required this.frame});

  @override
  List<Object?> get props => [frame];
}

// FaceDetectionModule main()
class DetectFacesUseCase implements UseCase<List<FaceBox>, DetectFacesParams> {
  IFaceDetector faceDetector;
  DetectFacesUseCase({required this.faceDetector});

  @override
  Future<Either<Failure, List<FaceBox>>> call(DetectFacesParams params) =>
      faceDetector.findFaces(params.frame);

  Future<void> dispose() => faceDetector.close();
}
