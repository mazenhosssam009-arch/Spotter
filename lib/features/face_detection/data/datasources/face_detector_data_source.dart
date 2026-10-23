import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart' as mp;
import 'package:ai_trainer/core/camera/camera_frame.dart';
import 'package:ai_trainer/core/camera/input_image_converter.dart';
import 'package:ai_trainer/core/error/exception.dart';
import 'package:ai_trainer/features/face_detection/domain/entities/face_box.dart';

// Google ML Kit face detection (on-device)
abstract class FaceDetectorDataSource {
  Future<List<FaceBox>> findFaces(CameraFrame frame);
  Future<void> close();
}

class FaceDetectorDataSourceImpl implements FaceDetectorDataSource {
  InputImageConverter inputImageConverter;
  final double minFaceSize;

  FaceDetectorDataSourceImpl({required this.inputImageConverter, this.minFaceSize = 0.1})
      : faceDetection = mp.FaceDetector(
          options: mp.FaceDetectorOptions(
            performanceMode: mp.FaceDetectorMode.fast,
            minFaceSize: minFaceSize,
          ),
        );

  final mp.FaceDetector faceDetection;

  @override
  Future<List<FaceBox>> findFaces(CameraFrame frame) async {
    final converted = inputImageConverter.convert(frame);
    if (converted == null) throw PoseException(code: 'unsupported-frame');
    final List<mp.Face> results;
    try {
      results = await faceDetection.processImage(converted.inputImage);
    } catch (_) {
      throw PoseException(code: 'face-detection-failed');
    }
    final s = converted.scale; // back to pixels of the full size picture
    return [
      for (var id = 0; id < results.length; id++)
        FaceBox(
          id: id,
          // mirrored picture (iOS front camera): the box's left edge is its mirrored right edge
          x: (converted.mirrored
                  ? converted.toX(results[id].boundingBox.right)
                  : converted.toX(results[id].boundingBox.left))
              .toInt(),
          y: (results[id].boundingBox.top * s).toInt(),
          width: (results[id].boundingBox.width * s).toInt(),
          height: (results[id].boundingBox.height * s).toInt(),
        ),
    ];
  }

  @override
  Future<void> close() => faceDetection.close();
}
