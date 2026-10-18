import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart' as mp;

import 'camera_view.dart';
import 'cv.dart';

class FaceDetector {
  FaceDetector({this.minFaceSize = 0.1})
      : faceDetection = mp.FaceDetector(
          options: mp.FaceDetectorOptions(
            performanceMode: mp.FaceDetectorMode.fast,
            minFaceSize: minFaceSize,
          ),
        );

  final double minFaceSize;
  final mp.FaceDetector faceDetection;

  /// returns [id, (x, y, w, h)] for every face.
  /// ML Kit does not give a detection score, so there is no "%" text.
  Future<List<List<Object>>> findFaces(Frame img, {bool draw = true}) async {
    final results = await faceDetection.processImage(img.input);
    final bboxs = <List<Object>>[];
    for (var id = 0; id < results.length; id++) {
      final s = img.detectScale; // back to pixels of the full size picture
      final b = results[id].boundingBox;
      final bbox = [(b.left * s).toInt(), (b.top * s).toInt(), (b.width * s).toInt(), (b.height * s).toInt()];
      bboxs.add([id, bbox]);
      if (draw) fancyDraw(img, bbox);
    }
    return bboxs;
  }

  void fancyDraw(Frame img, List<int> bbox, {int l = 30, double t = 10, double rt = 1}) {
    final x = bbox[0], y = bbox[1], w = bbox[2], h = bbox[3];
    final x1 = x + w, y1 = y + h;
    img.rectangle(x, y, x1, y1, blue, rt);
    // Top left x,y
    img.line(x, y, x + l, y, blue, t);
    img.line(x, y, x, y + l, blue, t);
    // Top right x1,y
    img.line(x1, y, x1 - l, y, blue, t);
    img.line(x1, y, x1, y + l, blue, t);
    // Bottom left x,y1
    img.line(x, y1, x + l, y1, blue, t);
    img.line(x, y1, x, y1 - l, blue, t);
    // Bottom right x1,y1
    img.line(x1, y1, x1 - l, y1, blue, t);
    img.line(x1, y1, x1, y1 - l, blue, t);
  }

  void close() => faceDetection.close();
}

/// main() of FaceDetectionModule
class FaceDetectionPage extends StatefulWidget {
  const FaceDetectionPage({super.key});

  @override
  State<FaceDetectionPage> createState() => _FaceDetectionPageState();
}

class _FaceDetectionPageState extends State<FaceDetectionPage> {
  final detector = FaceDetector();
  double ptime = 0;

  Future<void> onFrame(Frame img) async {
    final bboxs = await detector.findFaces(img);
    final ctime = now();
    final fps = 1 / (ctime - ptime);
    ptime = ctime;
    debugPrint('$bboxs');
    img.hud.putText('${fps.toInt()}', 10, 70, 3, magenta, 3);
  }

  @override
  void dispose() {
    detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CameraView(title: 'Face Detection', onFrame: onFrame);
}
