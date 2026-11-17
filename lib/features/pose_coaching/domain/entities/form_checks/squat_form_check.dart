import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_evaluation.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_geometry.dart';

/// squat: chest up (lean limit adapted to the user's proportions), stance and knee cave
class SquatFormCheck extends FormCheck {
  const SquatFormCheck();

  @override
  FormEvaluation check(FormCheckInput i) {
    final g = i.pose, e = i.exercise, per = i.per;
    final ev = FormEvaluation();
    final sh = g.mid(11, 12), hp = g.mid(23, 24), kn = g.mid(25, 26);
    if (sh != null && hp != null) {
      // trunk lean varies a lot with leg/torso proportions, so the limit adapts to the user:
      // long thighs (thigh / torso > 1) lean forward more, so they get a more generous limit.
      // The ratio is measured standing and frozen once the squat starts.
      var leanLim = e.limit('torsoLean', 60);
      if (kn != null) {
        final torso = (sh - hp).distance, thigh = (hp - kn).distance;
        if (torso > 1 && thigh > 1) {
          final r = i.baseline.follow('legTorso', thigh / torso, per < 15);
          leanLim += ((r - 1.0) * 40).clamp(-10.0, 20.0).toDouble();
        }
      }
      ev.limit(PoseGeometry.fromVertical(hp, sh) - leanLim, 20, 'Chest up - leaning far', block: true);
    }
    if (i.front == true) FormCheck.frontChecks(ev, i, 0.6, 2.0);
    ev.assessable = ev.scores.isNotEmpty;
    return ev;
  }
}
