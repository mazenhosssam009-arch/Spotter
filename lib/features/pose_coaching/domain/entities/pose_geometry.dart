import 'dart:math' as math;

import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/vec2.dart';

/// result of the bench "lying down" check, with the numbers it used (debug view)
class LyingReading {
  const LyingReading(this.lying, this.source, {this.tilt, this.ratio});

  /// true = torso horizontal (lying on a bench), false = clearly upright, null = unknown
  final bool? lying;

  /// which landmarks were used: 'hips', 'head' or 'none'
  final String source;

  /// torso tilt from vertical in degrees; null = not measured
  final double? tilt;

  /// torso length / shoulder width; -1 = not measured, null = not measured at all
  final double? ratio;
}

/// The geometry of ONE pose frame: landmark points, joint angles and the camera view.
/// Pure and stateless (the user's own posture lives in PostureBaseline).
class PoseGeometry {
  const PoseGeometry(this.frame);

  final PoseFrame frame;

  bool get hasPerson => frame.hasPerson;

  /// true when all these landmarks are really seen
  bool visible(List<int> ids) => frame.isVisible(ids);

  /// landmark [id] in whole pixels (like lmList = [id, cx, cy]), null when nobody is seen
  Vec2? point(int id) {
    if (!frame.hasPerson) return null;
    final q = frame.landmark(id);
    return Vec2(q.x.toInt().toDouble(), q.y.toInt().toDouble());
  }

  /// middle of two landmarks, using only the visible ones
  Vec2? mid(int a, int b) {
    final pts = <Vec2>[];
    for (final id in [a, b]) {
      final q = point(id);
      if (q != null && visible([id])) pts.add(q);
    }
    if (pts.isEmpty) return null;
    return pts.length == 1 ? pts[0] : (pts[0] + pts[1]) / 2;
  }

  /// angle at [b] in degrees (0-180)
  static double angle(Vec2 a, Vec2 b, Vec2 c) {
    final v1 = a - b, v2 = c - b;
    final d = v1.distance * v2.distance;
    if (d < 1e-6) return double.nan;
    final c0 = ((v1.dx * v2.dx + v1.dy * v2.dy) / d).clamp(-1.0, 1.0).toDouble();
    return math.acos(c0) * 180 / math.pi;
  }

  /// how far the line from->to is tilted away from vertical (0 = straight up/down)
  static double fromVertical(Vec2 from, Vec2 to) =>
      math.atan2((to.dx - from.dx).abs(), (to.dy - from.dy).abs()) * 180 / math.pi;

  /// make the angle 0-180 no matter which way you face the camera
  static double fold(double angle) => angle > 180 ? 360 - angle : angle;

  /// PoseModule.findAngle: whole pixels like lmList, 0-360 degrees
  double findAngle(List<int> joints) {
    final p1 = frame.landmark(joints[0]), p2 = frame.landmark(joints[1]), p3 = frame.landmark(joints[2]);
    final x1 = p1.x.toInt(), y1 = p1.y.toInt();
    final x2 = p2.x.toInt(), y2 = p2.y.toInt();
    final x3 = p3.x.toInt(), y3 = p3.y.toInt();
    var angle = (math.atan2(y3 - y2, x3 - x2) - math.atan2(y1 - y2, x1 - x2)) * 180 / math.pi;
    if (angle < 0) angle += 360;
    return angle;
  }

  /// true = facing the camera (shoulders wide compared with the torso), false = side on,
  /// null = unknown. [ratioLimit] = shoulder width / torso length above which it is frontal.
  bool? frontal(double ratioLimit) {
    final a = point(11), b = point(12), c = point(23), d = point(24);
    if (a == null || b == null || c == null || d == null || !visible([11, 12, 23, 24])) {
      return null;
    }
    final tl = ((a + b) / 2 - (c + d) / 2).distance;
    if (tl < 1) return null;
    return (a - b).distance / tl > ratioLimit;
  }

  /// how far the worst knee is inside its toes (0 = over the toes), as a fraction
  /// of shin length. Uses the toe, so a deliberate toe-out stance is not punished.
  double? kneeCave() {
    final h1 = point(23), h2 = point(24);
    if (h1 == null || h2 == null) return null;
    final mx = (h1.dx + h2.dx) / 2;
    double? worst;
    for (final s in const [
      [25, 27, 31],
      [26, 28, 32]
    ]) {
      if (!visible([s[0], s[1]])) continue;
      final kn = point(s[0]), an = point(s[1]), toe = point(s[2]);
      if (kn == null || an == null) continue;
      final Vec2 ft = (toe != null && visible([s[2]])) ? toe : an;
      final shin = (kn - an).distance;
      if (shin < 1) continue;
      final inward = ((mx - ft.dx).abs() - (mx - kn.dx).abs()) / shin;
      worst = worst == null ? inward : math.max(worst, inward);
    }
    return worst;
  }

  /// Is the torso horizontal (lying on a bench)? "false" is only returned when the hips are
  /// really seen AND the torso is vertical AND not foreshortened. When the hips are hidden
  /// (very common lying down) the answer is "unknown" and the bench press is NOT blocked,
  /// because a vertical head-shoulder line also looks vertical from the head/foot end.
  LyingReading lying({required double tiltLimit, required double ratioLimit}) {
    final sh = <Vec2>[], hp = <Vec2>[];
    for (final s in const [
      [11, 23],
      [12, 24]
    ]) {
      if (!visible(s)) continue;
      final a = point(s[0]), b = point(s[1]);
      if (a != null && b != null) {
        sh.add(a);
        hp.add(b);
      }
    }
    if (sh.isNotEmpty) {
      final s = sh.length == 2 ? (sh[0] + sh[1]) / 2 : sh[0];
      final h = hp.length == 2 ? (hp[0] + hp[1]) / 2 : hp[0];
      final tl = (s - h).distance;
      if (tl >= 1) {
        final tilt = fromVertical(h, s);
        if (tilt >= tiltLimit) return LyingReading(true, 'hips', tilt: tilt, ratio: -1); // side view
        var ratio = -1.0;
        if (sh.length == 2) {
          // head/foot end: the torso is foreshortened compared with the shoulder width
          ratio = tl / math.max((sh[0] - sh[1]).distance, 1.0);
          if (ratio < ratioLimit) return LyingReading(true, 'hips', tilt: tilt, ratio: ratio);
        }
        // hips seen, torso vertical and full length = really upright
        return LyingReading(false, 'hips', tilt: tilt, ratio: ratio);
      }
    }
    // hips hidden: the head line can PROVE lying (horizontal), but a vertical head line
    // proves nothing -> unknown, don't block
    for (final s in const [
      [7, 11],
      [8, 12],
      [0, 11],
      [0, 12]
    ]) {
      if (!visible(s)) continue;
      final head = point(s[0]), shoulder = point(s[1]);
      if (head == null || shoulder == null || (head - shoulder).distance < 1) continue;
      final tilt = fromVertical(shoulder, head);
      return LyingReading(tilt >= tiltLimit ? true : null, 'head', tilt: tilt, ratio: -1);
    }
    return const LyingReading(null, 'none');
  }
}
