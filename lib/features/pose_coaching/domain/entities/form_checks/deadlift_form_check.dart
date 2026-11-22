import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_evaluation.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_geometry.dart';

/// deadlift (conventional, sumo, romanian): neutral spine, knee bend at the bottom, stance
class DeadliftFormCheck extends FormCheck {
  const DeadliftFormCheck();

  @override
  FormEvaluation check(FormCheckInput i) {
    final g = i.pose, e = i.exercise, per = i.per, deadFront = i.deadFront;
    final ev = FormEvaluation();
    final rdl = e.variant == 'romanian', sumo = e.variant == 'sumo';
    final low = per >= 60; // lower part of the lift
    // spine proxy: ear-shoulder-hip compared with the lifter's own upright posture.
    // It cannot see the lumbar spine, so it only warns and never rejects a rep.
    var spineSeen = deadFront; // facing the camera: spine angle cannot be seen
    for (final s
        in deadFront
            ? const <List<int>>[]
            : const [
                [8, 12, 24],
                [7, 11, 23],
              ]) {
      if (!g.visible(s)) continue;
      final a = g.point(s[0]), b = g.point(s[1]), c = g.point(s[2]);
      if (a == null || b == null || c == null) continue;
      final ang = PoseGeometry.angle(a, b, c);
      if (!ang.isFinite) continue;
      ev.limit(
        (i.baseline.follow('neck', ang, i.idle) - ang) -
            e.limit('spineDrift', 25),
        15,
        'Keep spine neutral',
      );
      spineSeen = true;
      break;
    }
    if (deadFront) {
      ev.note = 'Facing camera: back not checked (film from the side)';
    } else if (!spineSeen) {
      ev.note = 'Head/back not visible';
    }
    // knee bend at the bottom depends on the variation
    final kLo = e.limit('kneeMin', rdl ? 135 : (sumo ? 70 : 85));
    final kHi = e.limit('kneeMax', rdl ? 178 : (sumo ? 140 : 150));
    final ks = <double>[];
    for (final s in const [
      [24, 26, 28],
      [23, 25, 27],
    ]) {
      if (!g.visible(s)) continue;
      final a = g.point(s[0]), b = g.point(s[1]), c = g.point(s[2]);
      if (a == null || b == null || c == null) continue;
      final ang = PoseGeometry.angle(a, b, c);
      if (ang.isFinite) ks.add(ang);
    }
    if (ks.isNotEmpty && !deadFront) {
      final knee = ks.reduce((a, b) => a + b) / ks.length;
      ev.limit(low ? kLo - knee : -1, 25, 'Too much knee bend');
      ev.limit(low ? knee - kHi : -1, 25, 'Knees too straight');
    }
    // conventional stance is about hip width (narrower than the shoulders), so 0.4 not 0.6.
    // Facing the camera, knees caving in and a too narrow stance now REJECT the rep: the
    // RepCounter checks them in _finishRep (RepCounter.deadFaultRejects). blockAt 0.0 = the
    // rep is rejected as soon as the warning limit is passed.
    if (i.front == true) {
      FormCheck.frontChecks(
        ev,
        i,
        sumo ? 1.4 : 0.4,
        sumo ? 3.0 : 1.6,
        caveLim: 0.30,
        blockCave: true,
        caveBlockAt: 0.0,
        blockStance: true,
      );
    }
    ev.assessable = ev.scores.isNotEmpty;
    return ev;
  }
}
