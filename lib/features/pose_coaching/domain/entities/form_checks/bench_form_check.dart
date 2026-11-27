import 'dart:math' as math;

import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_evaluation.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_geometry.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/vec2.dart';

/// shown when the elbows cannot be judged from this phone position (side view, foot end):
/// only the head end at bench height reads the flare well (3D test, see bench_views_sim_test)
const benchElbowTip = 'Put the phone behind your head to check elbows';

/// bench press: elbow flare, wrist over elbow, wrist straight, bar path, controlled
/// lowering, glutes on the bench, even bar
class BenchFormCheck extends FormCheck {
  const BenchFormCheck();

  @override
  FormEvaluation check(FormCheckInput i) {
    final g = i.pose, e = i.exercise, per = i.per, front = i.front;
    final ev = FormEvaluation();
    final flares = <double>[], tilts = <double>[], bends = <double>[];
    final wrists = <Vec2>[];
    var segs = 0.0;
    var sides = 0;
    for (final s in [e.right, if (e.left != null) e.left!]) {
      if (!g.visible(s)) continue;
      final sh = g.point(s[0]), el = g.point(s[1]), wr = g.point(s[2]);
      if (sh == null || el == null || wr == null) continue;
      final isRight = s[0] == 12;
      final hipId = isRight ? 24 : 23, idxId = isRight ? 20 : 19;
      final idx = g.visible([idxId]) ? g.point(idxId) : null;
      final flare = g.shoulderFlare(hipId, s[0], s[1], armRef: i.baseline['upperArmSw']);
      if (flare != null) flares.add(flare); // elbow-to-torso angle at the shoulder
      tilts.add(PoseGeometry.fromVertical(el, wr)); // forearm vs vertical
      if (idx != null) bends.add(PoseGeometry.angle(el, wr, idx)); // wrist straightness
      wrists.add(wr);
      segs += (sh - el).distance + (el - wr).distance;
      sides++;
    }
    if (sides == 0) return ev;
    final fl = flares.where((v) => v.isFinite).toList();
    final tl = tilts.where((v) => v.isFinite).toList();
    final bd = bends.where((v) => v.isFinite).toList();
    // elbow flare: a range, not one universal angle (bottom half only)
    // From the SIDE the elbow-to-torso angle is about 90 degrees on every normal rep,
    // so flare can only be judged from the head/foot end.
    if (front == true && fl.isNotEmpty) {
      // Warn past flareMax and call it a clear fault past flareReject (the voice coach
      // speaks at once; the RepCounter rejects the rep itself once the flare lasts).
      // With the elbows straight out the bar sits over the shoulder joint and the arm
      // is in the impingement range, the classic bench-press injury.
      // See PoseGeometry.shoulderFlare: tucked is 45-70, straight out 90. The bands leave
      // room for pose noise, so only a really wide flare throws the rep away.
      // The raw angle jumps by +-10 degrees from frame to frame end-on, so the SMOOTHED
      // flare (i.flare, the same one the rep rejection uses) is judged. Without it nothing
      // is judged this frame: a noisy number would only make the coach nag.
      final flareNow = i.flare;
      // head end detected (RepCounter.benchHeadEnd): the calibrated '...Head' limits
      final k = (i.baseline['benchHeadEnd'] ?? 0) > 0.5 ? 'Head' : '';
      // head end: the reject limit follows the phone height (RepCounter.flareRejectLimit)
      final reject = k == 'Head' ? (i.baseline['flareRejectNow'] ?? e.limit('flareRejectHead', 77.5)) : e.limit('flareReject', 100);
      if (flareNow != null) {
        ev.limit(
            per >= 50 ? flareNow - e.limit('flareMax$k', 80) : -1,
            20,
            'Elbows flared wide',
            block: true,
            blockAt: reject - e.limit('flareMax$k', 80));
      }
      ev.limit(per >= 50 ? e.limit('flareMin$k', 30) - fl.reduce(math.min) : -1, 15, 'Elbows tucked in');
    } else if (front == false) {
      ev.note = benchElbowTip; // from the side the flare is not in the picture at all
    } else if (front == null) {
      ev.note = 'Hips hidden - flare unchecked';
    } else {
      ev.note = 'Flare unchecked'; // arm length not learned yet / arm points at the lens
    }
    // foot end: the flare reads too high / out of order there, so the elbows are only loosely
    // watched (lenient limits); tell the user where they can be checked properly
    if (front == true && (i.baseline['benchFootEnd'] ?? 0) > 0.5) ev.note = benchElbowTip;
    // forearm should be close to vertical near the chest (wrist stacked over elbow)
    if (tl.isNotEmpty) {
      ev.limit(per >= 70 ? tl.reduce(math.max) - e.limit('forearmTilt', 25) : -1, 20, 'Stack wrist over elbow');
    }
    // wrist alignment: elbow-wrist-knuckle should be near straight
    if (bd.isNotEmpty) {
      ev.limit(per >= 30 ? e.limit('wristMin', 145) - bd.reduce(math.min) : -1, 25, 'Wrist bent back');
    }
    // bar path (the wrists stand in for the bar): sideways drift from the start line
    final x = wrists.map((p) => p.dx).reduce((a, b) => a + b) / wrists.length;
    final seg = segs / (2 * sides);
    if (seg > 1) {
      ev.limit((x - i.baseline.follow('barX', x, i.idle)).abs() / seg - 0.5, 0.4, 'Bar path drifting');
    }
    // controlled lowering: dropping the bar fast (bouncing it off the chest) is a classic
    // chest / shoulder injury
    if (i.lowering) {
      ev.limit(i.speed - e.limit('descentMax', 160), 120, 'Lower slowly - control the bar');
    }
    // glutes must stay on the bench (side view): the shoulder-hip line keeps its start angle
    if (front != true && i.lyingSeen) {
      for (final s in const [
        [11, 23],
        [12, 24]
      ]) {
        if (!g.visible(s)) continue;
        final a = g.point(s[0]), b = g.point(s[1]);
        if (a == null || b == null || (a - b).distance < 1) continue;
        final tilt = PoseGeometry.fromVertical(b, a);
        ev.limit((tilt - i.baseline.follow('benchTilt${s[0]}', tilt, i.idle)).abs() - e.limit('hipLift', 12), 15,
            'Keep glutes on the bench');
        break;
      }
    }
    // uneven bar (facing the camera): one wrist higher than the other
    final s1 = g.point(11), s2 = g.point(12);
    if (front == true && wrists.length == 2 && s1 != null && s2 != null) {
      final sw = (s1 - s2).distance;
      if (sw > 1) {
        ev.limit((wrists[0].dy - wrists[1].dy).abs() / sw - e.limit('barTilt', 0.25), 0.25, 'Bar uneven');
      }
    }
    ev.assessable = true;
    return ev;
  }
}
