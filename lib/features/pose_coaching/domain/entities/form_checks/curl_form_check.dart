import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_evaluation.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_geometry.dart';

/// biceps curl: elbow drift, body swing, shrug, torso twist
class CurlFormCheck extends FormCheck {
  const CurlFormCheck();

  @override
  FormEvaluation check(FormCheckInput i) {
    final g = i.pose, e = i.exercise, base = i.baseline, idle = i.idle;
    final ev = FormEvaluation();
    // one arm or both arms (see armMode): every active arm is checked
    for (final arm in [e.right, if (e.left != null) e.left!]) {
      final isRight = arm[0] == 12;
      final hipId = isRight ? 24 : 23, otherShId = isRight ? 11 : 12;
      final s = g.point(arm[0]), el = g.point(arm[1]), hip = g.point(hipId);
      if (s == null || el == null || hip == null || !g.visible([arm[0], arm[1], hipId])) {
        continue; // hip hidden: swing cannot be judged for this arm
      }
      final torso = (s - hip).distance;
      if (torso < 1) continue;
      // 1) upper arm should stay near the torso; elbow swinging forward = shoulder is helping
      ev.limit(PoseGeometry.angle(hip, s, el) - e.limit('elbowDrift', 25), 30, 'Elbow drifting forward',
          block: true, blockAt: e.limit('elbowDriftReject', 30));
      // 2) body swing: torso lean compared with the user's own start posture
      final lean = PoseGeometry.fromVertical(hip, s);
      // side on, the far hip is partly hidden and wobbles, so this only REJECTS a rep
      // when the body really moves (swing + swingReject degrees from the start posture)
      ev.limit((lean - base.follow('lean$hipId', lean, idle)).abs() - e.limit('swing', 12), 20,
          'Swinging - stay still',
          block: true, blockAt: e.limit('swingReject', 20));
      // 3) shoulder shrug: torso length (hip to shoulder) changes
      ev.limit(((torso / base.follow('torso$hipId', torso, idle)) - 1).abs() - e.limit('shrug', 0.12), 0.12,
          i.curlFront ? 'Leaning - keep still' : 'Shoulders shrugging');
      // 4) torso twist: shoulder width changes a lot
      final s2 = g.point(otherShId);
      if (s2 != null && g.visible([otherShId])) {
        final sw = (s - s2).distance;
        ev.limit(((sw / base.follow('sw$hipId', sw, idle)) - 1).abs() - e.limit('twist', 0.2), 0.2,
            'Torso twisting');
      }
      // 5) ONLY when facing the camera (curlFront): an elbow moving forward points at the
      // lens, so check 1 cannot see it. The upper arm then looks SHORTER than at the start.
      // Warn only (never rejects), and it does nothing at all when filmed from the side.
      if (i.curlFront) {
        final ua = (s - el).distance;
        final ba = base.follow('ua$hipId', ua, idle);
        if (ba > 1) {
          ev.limit(1 - ua / ba - e.limit('armShorten', 0.25), 0.25, 'Elbow drifting forward');
        }
      }
      ev.assessable = true;
    }
    return ev;
  }
}
