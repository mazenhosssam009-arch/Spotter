import 'package:flutter/material.dart';

import 'camera_view.dart';
import 'cv.dart';
import 'pose_module.dart';

/// main() of PoseModule.py / Pose
class PosePage extends StatefulWidget {
  const PosePage({super.key});

  @override
  State<PosePage> createState() => _PosePageState();
}

class _PosePageState extends State<PosePage> {
  final detector = PoseDetector();
  double ptime = 0;

  Future<void> onFrame(Frame img) async {
    await detector.findPose(img);
    final lmList = detector.findPosition(img);
    if (lmList.isNotEmpty) debugPrint('${lmList[4]}');
    final ctime = now();
    final fps = 1 / (ctime - ptime);
    ptime = ctime;
    img.hud.putText('${fps.toInt()}', 10, 70, 3, magenta, 3);
  }

  @override
  void dispose() {
    detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CameraView(title: 'Pose Estimation', onFrame: onFrame);
}
