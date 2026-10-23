import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart' as mp;
import 'package:ai_trainer/core/error/exception.dart';
import 'package:ai_trainer/core/camera/input_image_converter.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/body_landmark.dart';
import 'package:ai_trainer/core/camera/camera_frame.dart';

/// false = ML Kit "base" model: clearly faster on most phones, good enough for lifting form.
/// true = "accurate" model (closest to mediapipe model_complexity=1) but it can halve the FPS.
const useAccurateModel = false;

// Google ML Kit pose detection (BlazePose, 33 landmarks, on-device)
abstract class PoseDetectorDataSource {
  /// the landmarks of the first person in picture pixels, empty when nobody is seen
  Future<List<BodyLandmark>> detect(CameraFrame frame);
  Future<void> close();
}

class PoseDetectorDataSourceImpl implements PoseDetectorDataSource {
  InputImageConverter inputImageConverter;
  PoseDetectorDataSourceImpl({required this.inputImageConverter});

  // stream mode = mediapipe static_image_mode=False (tracks between frames)
  final mp.PoseDetector pose = mp.PoseDetector(
    options: mp.PoseDetectorOptions(
      mode: mp.PoseDetectionMode.stream,
      model: useAccurateModel ? mp.PoseDetectionModel.accurate : mp.PoseDetectionModel.base,
    ),
  );

  @override
  Future<List<BodyLandmark>> detect(CameraFrame frame) async {
    final converted = inputImageConverter.convert(frame);
    if (converted == null) throw PoseException(code: 'unsupported-frame');
    final List<mp.Pose> poses;
    try {
      poses = await pose.processImage(converted.inputImage);
    } catch (_) {
      throw PoseException(code: 'pose-detection-failed');
    }
    if (poses.isEmpty) return const [];
    // back to pixels of the full size picture
    final s = converted.scale;
    final lms = poses.first.landmarks;
    final out = <BodyLandmark>[];
    for (final type in mp.PoseLandmarkType.values) {
      // mirrored picture (iOS front camera): ML Kit sees a mirror image of the person, so it
      // calls their left side "right". Read each id from its mirrored partner so the landmarks
      // are the same as on Android (real left / right, not mirrored).
      final l = lms[converted.mirrored ? mp.PoseLandmarkType.values[_otherSide(type.index)] : type];
      if (l == null) continue;
      out.add(BodyLandmark(id: type.index, x: converted.toX(l.x), y: l.y * s, z: l.z * s, likelihood: l.likelihood));
    }
    return out;
  }

  /// the same landmark on the other side of the body: eyes 1-3 <-> 4-6, then 7<->8, 9<->10 ... 31<->32
  static int _otherSide(int i) {
    if (i == 0) return 0; // nose
    if (i <= 3) return i + 3; // left eye -> right eye
    if (i <= 6) return i - 3; // right eye -> left eye
    return i.isOdd ? i + 1 : i - 1; // 7<->8, 9<->10, ... 31<->32
  }

  @override
  Future<void> close() => pose.close();
}
