import 'package:ai_trainer/core/widgets/overlay_canvas.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/joint_angle.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';

// mpDraw.draw_landmarks: white connections, red points
void drawLandmarks(OverlayFrame img, PoseFrame pose) {
  if (!pose.hasPerson) return;
  for (final c in PoseFrame.connections) {
    final a = pose.landmark(c[0]), b = pose.landmark(c[1]);
    if (a.likelihood > 0.5 && b.likelihood > 0.5) {
      img.line(a.x.toInt(), a.y.toInt(), b.x.toInt(), b.y.toInt(), white, 2);
    }
  }
  for (final l in pose.landmarks) {
    if (l.likelihood > 0.5) img.circle(l.x.toInt(), l.y.toInt(), 3, red, filled);
  }
}

// PoseModule.findPosition(draw=True): a blue dot on every landmark
void drawPositions(OverlayFrame img, PoseFrame pose) {
  for (final l in pose.landmarks) {
    img.circle(l.x.toInt(), l.y.toInt(), 5, blue, filled);
  }
}

// PoseModule.findAngle(draw=True): the 3 joints, the 2 lines and the angle
void drawAngle(OverlayFrame img, PoseFrame pose, JointAngle a) {
  final p1 = pose.landmark(a.joints[0]), p2 = pose.landmark(a.joints[1]), p3 = pose.landmark(a.joints[2]);
  final x1 = p1.x.toInt(), y1 = p1.y.toInt();
  final x2 = p2.x.toInt(), y2 = p2.y.toInt();
  final x3 = p3.x.toInt(), y3 = p3.y.toInt();
  img.line(x1, y1, x2, y2, black, 3);
  img.line(x3, y3, x2, y2, black, 3);
  img.circle(x1, y1, 5, red, filled);
  img.circle(x1, y1, 10, red, 2);
  img.circle(x2, y2, 5, red, filled);
  img.circle(x2, y2, 10, red, 2);
  img.circle(x3, y3, 5, red, filled);
  img.circle(x3, y3, 10, red, 2);
  img.putText('${a.angle.toInt()}', x2 + 10, y2 - 30, 1.5, magenta, 2);
}
