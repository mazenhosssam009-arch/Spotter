import 'dart:math' as math;

import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_evaluation.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_geometry.dart';

/// biceps curl: shoulder and elbow movement, elbow drift, body swing, shrug, torso twist
class CurlFormCheck extends FormCheck {
  const CurlFormCheck();

  /// raised, tense shoulders (also used by the RepCounter and the voice coach)
  static const raisedMsg = 'Shoulders raised - relax them';

  @override
  FormEvaluation check(FormCheckInput i) {
    final g = i.pose, e = i.exercise, base = i.baseline, idle = i.idle;
    final ev = FormEvaluation();
    // facing the camera the picture shows less of every swing, so all the curl limits below
    // are multiplied by frontStrict (0.75 = 25% stricter). Side view: k = 1, nothing changes.
    final k = i.curlFront ? e.limit('frontStrict', 0.75) : 1.0;
    // one arm or both arms (see armMode): every active arm is checked
    for (final arm in [e.right, if (e.left != null) e.left!]) {
      final isRight = arm[0] == 12;
      final hipId = isRight ? 24 : 23, otherShId = isRight ? 11 : 12;
      final s = g.point(arm[0]), el = g.point(arm[1]);
      if (s == null || el == null || !g.visible([arm[0], arm[1]])) continue;
      final ua = (s - el).distance; // upper arm length in the picture
      // 0) checks that need NO hip (they work even when the hips are out of the picture).
      // Ruler = the user's own upper arm length at the start, so the distance to the phone
      // does not matter. The start posture is frozen during a rep.
      final ruler = base.quickFollow('uaLen${arm[0]}', ua, idle);
      if (ruler > 1) {
        // 0a) the shoulder must not move (shrug, rocking, back swing, body swing):
        // warns at shoulderMove upper-arm lengths, REJECTS at shoulderMove + shoulderMoveReject
        final bsx = base.quickFollow('shX${arm[0]}', s.dx, idle);
        final bsy = base.quickFollow('shY${arm[0]}', s.dy, idle);
        final sdx = s.dx - bsx, sdy = s.dy - bsy;
        ev.limit(
          math.sqrt(sdx * sdx + sdy * sdy) / ruler -
              e.limit('shoulderMove', 0.12) * k,
          0.2,
          'Shoulder moving - stay still',
          block: true,
          blockAt: e.limit('shoulderMoveReject', 0.08) * k,
        );
        // 0b) the elbow must stay where it started, beside the body (relative to the shoulder):
        // warns at elbowMove upper-arm lengths, REJECTS at elbowMove + elbowMoveReject
        final box = base.quickFollow('elX${arm[0]}', el.dx - s.dx, idle);
        final boy = base.quickFollow('elY${arm[0]}', el.dy - s.dy, idle);
        final edx = (el.dx - s.dx) - box, edy = (el.dy - s.dy) - boy;
        ev.limit(
          math.sqrt(edx * edx + edy * edy) / ruler -
              e.limit('elbowMove', 0.25) * k,
          0.3,
          'Elbow moving - keep it by your side',
          block: true,
          blockAt: e.limit('elbowMoveReject', 0.10) * k,
        );
        // 0c) raised, tense shoulders (a shrug): the shoulder rises toward the ear, so the
        // ear-to-shoulder distance shrinks. A neck is short, so this is far more sensitive than
        // the torso length (check 3). The reference is the LONGEST (most relaxed) neck seen while
        // idle, in upper-arm lengths, so someone who starts the set tense is caught as soon as
        // they have relaxed once. WARNING ONLY: it warns at shoulderRaise (fraction shorter
        // than relaxed) but never rejects the rep (the ear landmark is too noisy when the phone
        // is a bit uneven). Skipped when the ear on this side is not seen (filmed from the
        // other side).
        final earId = isRight ? 8 : 7;
        final ear = g.point(earId);
        if (ear != null && g.visible([earId])) {
          final neck = (ear - s).distance / ruler;
          final relaxed = base.standing('neck${arm[0]}', neck, idle);
          if (relaxed > 0) {
            ev.limit(
              1 - neck / relaxed - e.limit('shoulderRaise', 0.10),
              0.15,
              raisedMsg,
            );
          }
        }
        ev.assessable = true;
      }
      // hip based checks (only when the hip is seen)
      final hip = g.point(hipId);
      if (hip != null && g.visible([hipId])) {
        final torso = (s - hip).distance;
        if (torso > 1) {
          // 1) the elbow must stay beside the body: the upper arm may only leave the torso a little.
          // Warns at elbowDrift degrees and REJECTS the rep at elbowDrift + elbowDriftReject
          ev.limit(
            PoseGeometry.angle(hip, s, el) - e.limit('elbowDrift', 15) * k,
            30,
            'Elbow drifting forward',
            block: true,
            blockAt: e.limit('elbowDriftReject', 10) * k,
          );
          // 2) body swing: torso lean compared with the user's own start posture.
          // Warns at swing degrees and REJECTS the rep at swing + swingReject
          final lean = PoseGeometry.fromVertical(hip, s);
          ev.limit(
            (lean - base.follow('lean$hipId', lean, idle)).abs() -
                e.limit('swing', 8) * k,
            20,
            'Swinging - stay still',
            block: true,
            blockAt: e.limit('swingReject', 5) * k,
          );
          // 3) shoulder shrug / shoulders rocking: torso length (hip to shoulder) changes.
          // Warns at shrug and REJECTS the rep at shrug + shrugReject
          ev.limit(
            ((torso / base.follow('torso$hipId', torso, idle)) - 1).abs() -
                e.limit('shrug', 0.08) * k,
            0.12,
            i.curlFront ? 'Leaning - keep still' : 'Shoulders shrugging',
            block: true,
            blockAt: e.limit('shrugReject', 0.04) * k,
          );
          ev.assessable = true;
        }
      }
      // 4) torso twist: shoulder width changes a lot
      final s2 = g.point(otherShId);
      if (s2 != null && g.visible([otherShId])) {
        final sw = (s - s2).distance;
        ev.limit(
          ((sw / base.follow('sw$hipId', sw, idle)) - 1).abs() -
              e.limit('twist', 0.2),
          0.2,
          'Torso twisting',
        );
      }
      // 5) ONLY when facing the camera (curlFront): an elbow moving forward points at the
      // lens, so check 1 cannot see it. The upper arm then looks SHORTER than at the start.
      // Rejects the rep once the upper arm looks armShorten + armShortenReject shorter,
      // and it does nothing at all when filmed from the side.
      if (i.curlFront) {
        final ba = base.follow('ua$hipId', ua, idle);
        if (ba > 1) {
          ev.limit(
            1 - ua / ba - e.limit('armShorten', 0.08) * k,
            0.25,
            'Elbow drifting forward',
            block: true,
            blockAt: e.limit('armShortenReject', 0.05) * k,
          );
        }
      }
    }
    return ev;
  }
}
