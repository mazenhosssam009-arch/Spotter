import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_evaluation.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_geometry.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/posture_baseline.dart';

/// everything a form check may look at in one frame
class FormCheckInput {
  const FormCheckInput({
    required this.pose,
    required this.exercise,
    required this.per,
    required this.idle,
    required this.front,
    required this.baseline,
    this.curlFront = false,
    this.deadFront = false,
    this.lowering = false,
    this.speed = 0,
    this.lyingSeen = false,
    this.flare,
  });

  final PoseGeometry pose;

  /// the exercise with the arm(s) the user picked
  final Exercise exercise;

  /// depth of the current rep, 0..100
  final double per;

  /// between reps (the start posture may follow the user)
  final bool idle;

  /// true = facing the camera, false = side on, null = unknown
  final bool? front;
  final PostureBaseline baseline;

  /// curl / deadlift filmed facing the camera (frozen during a rep)
  final bool curlFront, deadFront;

  /// on the way down, before the bottom
  final bool lowering;

  /// smoothed angular speed, deg/s
  final double speed;

  /// bench: the lifter has been seen lying down
  final bool lyingSeen;

  /// bench: the elbow flare (worst arm) smoothed in time by the RepCounter, null = no reading.
  /// The form check judges THIS, not the raw per-frame angle, so the warning, the coach and
  /// the form score see the same steady number the rep rejection uses.
  final double? flare;
}

/// the form rules of one exercise for one frame
abstract class FormCheck {
  const FormCheck();

  FormEvaluation check(FormCheckInput i);

  /// stance width (ankles / shoulders) and knee cave: only meaningful facing the camera
  static void frontChecks(FormEvaluation ev, FormCheckInput i, double sMin, double sMax,
      {double caveLim = 0.15, bool blockCave = true}) {
    final g = i.pose, e = i.exercise;
    final a1 = g.point(27), a2 = g.point(28), s1 = g.point(11), s2 = g.point(12);
    if (a1 != null && a2 != null && s1 != null && s2 != null && g.visible([27, 28])) {
      final sw = (s1 - s2).distance;
      if (sw > 1) {
        final ratio = (a1 - a2).distance / sw;
        ev.limit(e.limit('stanceMin', sMin) - ratio, 0.3, 'Stance too narrow');
        ev.limit(ratio - e.limit('stanceMax', sMax), 0.5, 'Stance too wide');
      }
    }
    final cave = g.kneeCave();
    if (cave != null) {
      ev.limit(i.per >= 30 ? cave - e.limit('kneeCave', caveLim) : -1, 0.2, 'Knees caving in', block: blockCave);
    }
  }
}
