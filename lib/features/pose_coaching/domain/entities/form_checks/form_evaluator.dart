import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/bench_form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/curl_form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/deadlift_form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/squat_form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_evaluation.dart';

/// all form checks of one frame: the exercise's own rules, then the ones every exercise shares
class FormEvaluator {
  const FormEvaluator._();

  /// the rules of [e]; null = no form checks for this exercise
  static FormCheck? checkFor(Exercise e) => e.isCurl
      ? const CurlFormCheck()
      : e.isSquat
          ? const SquatFormCheck()
          : e.isDeadlift
              ? const DeadliftFormCheck()
              : e.isBench
                  ? const BenchFormCheck()
                  : null;

  /// [asym] = angle difference between the two sides (null = not measured)
  static FormEvaluation evaluate(FormCheckInput i, {double? asym}) {
    final e = i.exercise;
    final ev = checkFor(e)?.check(i) ?? FormEvaluation();
    // one side doing more work than the other (needs both sides and a frontal view)
    if (ev.assessable && asym != null && i.front == true) {
      ev.limit(i.per >= 40 ? asym - e.limit('asym', 25) : -1, 20, 'Uneven sides');
    }
    if (i.speed > 1.3 * e.maxSpeed) ev.warns.add('Slow down - control it');
    return ev;
  }
}
