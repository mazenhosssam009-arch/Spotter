import 'dart:math' as math;

import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/vec2.dart';

/// result of the bench "lying down" check, with the numbers it used (debug view)
class LyingReading {
  const LyingReading(this.lying, this.source, {this.tilt, this.ratio});

  /// true = torso horizontal (lying on a bench), false = clearly upright, null = unknown
  final bool? lying;

  /// which landmarks were used: 'hips', 'hips?' (grey zone), 'head-end', 'legs', 'head' or 'none'
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

  /// how surely the LEAST sure of these landmarks is seen (0..1)
  double confidence(List<int> ids) => ids
      .map((id) => frame.landmark(id).likelihood)
      .fold(1.0, (a, b) => math.min(a, b));

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

  /// Camera along the torso (head/foot end of the bench): the torso is squashed in the
  /// picture, so shoulder-to-hip length / shoulder width is small there.
  static const endOnSquash = 0.6;

  /// shoulder-to-hip length in the picture divided by the shoulder width in the picture
  /// (about 0 looking along the torso, 1+ from the side or at an angle). When the hips are
  /// hidden (very common lying down) the head stands in for them: the nose sits about half
  /// a torso length from the shoulder line, so its distance is doubled. null when the
  /// shoulders (and the hips or the nose) are not seen.
  double? torsoSquash() {
    if (!visible([11, 12])) return null;
    final a = point(11), b = point(12);
    if (a == null || b == null) return null;
    final sw = (a - b).distance;
    if (sw < 1) return null;
    final mid = (a + b) / 2;
    final c = point(23), d = point(24);
    if (c != null && d != null && visible([23, 24])) {
      return (mid - (c + d) / 2).distance / sw;
    }
    final n = point(0);
    if (n == null || !visible([0])) return null;
    return 2 * (n - mid).distance / sw;
  }

  /// The angle at the shoulder between the torso and the upper arm ("elbow flare"),
  /// in degrees: about 45-70 with the elbows tucked in, 90 with them straight out to
  /// the sides.
  ///
  /// Seen at an angle or from the side, the plain 2D angle between the torso line and the
  /// upper arm is right.
  ///
  /// Seen end-on (camera at the head/foot end) the torso line is a dot, so the 2D angle is
  /// meaningless (it read 150-180 on a tucked rep). The old fix used the depth z of the
  /// hip and the elbow, but ML Kit's z is its weakest coordinate and the hips are guessed
  /// there, so the angle jumped by +-20 degrees from frame to frame. Now neither is used:
  /// the torso axis points at the lens, so the flare is the angle in the horizontal plane
  /// between that axis and the upper arm,
  ///   flare = asin(sideways offset / sqrt(L^2 - vertical offset^2))
  /// with L = the real upper-arm length. [armRef] is L in shoulder widths (learned by the
  /// RepCounter, so the distance to the phone does not matter). It can only read 0..90.
  /// null when the angle cannot be read (arm hidden, arm length not learned yet or learned
  /// too short, or the upper arm points at the lens).
  double? shoulderFlare(int hipId, int shId, int elId, {double? armRef}) {
    if (!visible([shId, elId])) return null;
    final squash = torsoSquash();
    if (squash == null) return null; // cannot tell which formula applies
    if (squash < endOnSquash) {
      if (armRef == null) return null;
      final s = point(shId), e = point(elId), a = point(11), b = point(12);
      if (s == null || e == null || a == null || b == null) return null;
      final len = armRef * (a - b).distance;
      final dx = (e.dx - s.dx).abs(), dy = (e.dy - s.dy).abs();
      // the upper arm cannot look LONGER in the picture than it is: if it does, the learned
      // length is too short and every angle would read too high (up to 90 = "flared"), so
      // judge nothing until the RepCounter has learned a longer one
      if (math.sqrt(dx * dx + dy * dy) > 1.05 * len) return null;
      final inPlane = math.sqrt(math.max(len * len - dy * dy, 0.0));
      if (inPlane < 0.3 * len)
        return null; // arm points at the lens: no angle to read
      return math.asin((dx / inPlane).clamp(0.0, 1.0).toDouble()) *
          180 /
          math.pi;
    }
    if (!visible([hipId])) return null; // the 2D angle needs the hip
    final h = frame.landmark(hipId);
    final s = frame.landmark(shId);
    final e = frame.landmark(elId);
    final tx = h.x - s.x, ty = h.y - s.y;
    final ax = e.x - s.x, ay = e.y - s.y;
    final tl2 = math.sqrt(tx * tx + ty * ty); // torso in the picture
    final ua2 = math.sqrt(ax * ax + ay * ay); // upper arm in the picture
    if (tl2 < 1 || ua2 < 1) return null;
    final c = ((tx * ax + ty * ay) / (tl2 * ua2)).clamp(-1.0, 1.0);
    return math.acos(c) * 180 / math.pi;
  }

  /// The upper arm hangs straight DOWN beside the ribs (within [maxDeg] of vertical), the
  /// way it does in a curl or a row. A bench press never does this: the elbows are out to
  /// the sides at the bottom and the arms point up at lockout. Measured against the
  /// shoulder line, so the camera cannot fake it. The elbow must also be BELOW the shoulder
  /// in the picture: an arm pointing straight UP (bench press lockout, seen from the head
  /// or foot end) makes the very same 90 degree angle with the shoulder line, and used to
  /// be taken for a hanging arm - which closed the lying gate in the middle of a rep.
  /// null when the shoulders are seen from the side (no reference line) or the upper arm
  /// points at the lens.
  bool? upperArmHangs(int shId, int otherShId, int elId, {double maxDeg = 15}) {
    if (!visible([shId, otherShId, elId])) return null;
    final sh = point(shId), other = point(otherShId), el = point(elId);
    if (sh == null || other == null || el == null) return null;
    final width = (other - sh).distance;
    final arm = (el - sh).distance;
    if (width < 1 || arm < 1) return null;
    if (width < 0.6 * arm) return null; // side on: no usable reference line
    if (arm < 0.35 * width)
      return null; // arm points at the lens: no angle to read
    // angle at the shoulder between (towards the other shoulder) and (towards the elbow):
    // 90 = straight down beside the ribs, 180 = straight out sideways
    final a = angle(other, sh, el);
    if (!a.isFinite || a > 90 + maxDeg) return false;
    // up or down? take the perpendicular of the shoulder line that points down the picture
    final ux = other.dx - sh.dx, uy = other.dy - sh.dy;
    var nx = -uy, ny = ux;
    if (ny < 0) {
      nx = -nx;
      ny = -ny;
    }
    return (el.dx - sh.dx) * nx + (el.dy - sh.dy) * ny > 0;
  }

  /// angle at [b] in degrees (0-180)
  static double angle(Vec2 a, Vec2 b, Vec2 c) {
    final v1 = a - b, v2 = c - b;
    final d = v1.distance * v2.distance;
    if (d < 1e-6) return double.nan;
    final c0 = ((v1.dx * v2.dx + v1.dy * v2.dy) / d)
        .clamp(-1.0, 1.0)
        .toDouble();
    return math.acos(c0) * 180 / math.pi;
  }

  /// how far the line from->to is tilted away from vertical (0 = straight up/down)
  static double fromVertical(Vec2 from, Vec2 to) =>
      math.atan2((to.dx - from.dx).abs(), (to.dy - from.dy).abs()) *
      180 /
      math.pi;

  /// make the angle 0-180 no matter which way you face the camera
  static double fold(double angle) => angle > 180 ? 360 - angle : angle;

  /// PoseModule.findAngle: whole pixels like lmList, 0-360 degrees
  double findAngle(List<int> joints) {
    final p1 = frame.landmark(joints[0]),
        p2 = frame.landmark(joints[1]),
        p3 = frame.landmark(joints[2]);
    final x1 = p1.x.toInt(), y1 = p1.y.toInt();
    final x2 = p2.x.toInt(), y2 = p2.y.toInt();
    final x3 = p3.x.toInt(), y3 = p3.y.toInt();
    var angle =
        (math.atan2(y3 - y2, x3 - x2) - math.atan2(y1 - y2, x1 - x2)) *
        180 /
        math.pi;
    if (angle < 0) angle += 360;
    return angle;
  }

  /// true = facing the camera (shoulders wide compared with the torso), false = side on,
  /// null = unknown. [ratioLimit] = shoulder width / torso length above which it is frontal.
  bool? frontal(double ratioLimit) {
    final a = point(11), b = point(12), c = point(23), d = point(24);
    if (a == null ||
        b == null ||
        c == null ||
        d == null ||
        !visible([11, 12, 23, 24])) {
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
      [26, 28, 32],
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

  /// Looking along the torso for the LYING test only: a bit looser than [endOnSquash]
  /// because a camera that is also above/below the bench only half squashes the torso.
  static const lyingSquash = 0.75;

  /// A torso this much closer to vertical than the tilt limit, AND this much longer (in
  /// shoulder widths) than the ratio limit, is "clearly upright". Anything in between
  /// (oblique angles, a camera looking down at the bench, a slightly raised bench, noisy
  /// landmarks) is "unknown", which never blocks the exercise.
  static const _uprightTiltFactor = 0.6;
  static const _uprightRatioMargin = 0.15;

  /// Is the torso horizontal (lying on a bench)? Works from any side of the bench and at
  /// oblique / high / low camera angles by combining several independent cues:
  ///  1. side view: the shoulder-hip line is far from vertical in the picture,
  ///  2. head/foot end or a camera above: the torso is foreshortened compared with the
  ///     shoulder width (also with only one hip seen),
  ///  3. hips hidden: the shoulder-knee / shoulder-ankle line, the head-on-shoulders
  ///     (end-on) test, or the head line.
  /// "false" (upright, blocks the exercise) is only returned when the torso is clearly
  /// vertical AND clearly full length. Everything ambiguous is "unknown" (null), because
  /// a wrong "not lying" stops a real set while a wrong "unknown" only lets a rare
  /// non-bench movement through (the arms-hanging check still catches curls).
  LyingReading lying({required double tiltLimit, required double ratioLimit}) {
    final sh = <Vec2>[], hp = <Vec2>[];
    for (final s in const [
      [11, 23],
      [12, 24],
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
        if (tilt >= tiltLimit) {
          return LyingReading(true, 'hips', tilt: tilt, ratio: -1); // side view
        }
        var ratio = -1.0;
        final la = point(11), lb = point(12);
        if (la != null && lb != null && visible([11, 12])) {
          // head/foot end or camera above: torso foreshortened vs the shoulder width
          ratio = tl / math.max((la - lb).distance, 1.0);
          if (ratio < ratioLimit) {
            return LyingReading(true, 'hips', tilt: tilt, ratio: ratio);
          }
        }
        // Full-length and near vertical = really upright. In the grey zone (tilted a
        // little, or only a little longer than the limit) say "unknown" instead.
        final clearlyVertical = tilt < tiltLimit * _uprightTiltFactor;
        final clearlyLong =
            ratio < 0 || ratio >= ratioLimit + _uprightRatioMargin;
        if (clearlyVertical && clearlyLong) {
          return LyingReading(false, 'hips', tilt: tilt, ratio: ratio);
        }
        return LyingReading(null, 'hips?', tilt: tilt, ratio: ratio);
      }
    }
    // hips hidden. Only POSITIVE proof of lying is used here; a vertical line proves
    // nothing because it also looks vertical from the head/foot end.
    // (a) head/foot end: the head sits on top of the shoulder line
    final sq = torsoSquash();
    if (sq != null && sq < lyingSquash) {
      return LyingReading(true, 'head-end', tilt: null, ratio: sq);
    }
    // (b) shoulder -> knee / ankle line is far from vertical (legs bent or straight out
    // along the bench). Needs a bigger angle than the torso test: knees rise above the hips.
    final legLimit = math.max(tiltLimit + 15, 50.0);
    for (final s in const [
      [11, 25],
      [12, 26],
      [11, 27],
      [12, 28],
    ]) {
      if (!visible(s)) continue;
      final top = point(s[0]), low = point(s[1]);
      if (top == null || low == null || (top - low).distance < 1) continue;
      final tilt = fromVertical(low, top);
      if (tilt >= legLimit) {
        return LyingReading(true, 'legs', tilt: tilt, ratio: -1);
      }
    }
    // (c) the head line (ears / nose against the shoulder)
    for (final s in const [
      [7, 11],
      [8, 12],
      [0, 11],
      [0, 12],
    ]) {
      if (!visible(s)) continue;
      final head = point(s[0]), shoulder = point(s[1]);
      if (head == null || shoulder == null || (head - shoulder).distance < 1) {
        continue;
      }
      final tilt = fromVertical(shoulder, head);
      return LyingReading(
        tilt >= tiltLimit ? true : null,
        'head',
        tilt: tilt,
        ratio: -1,
      );
    }
    return const LyingReading(null, 'none');
  }
}
