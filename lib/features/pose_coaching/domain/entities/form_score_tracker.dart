import 'dart:math' as math;

import 'package:ai_trainer/features/pose_coaching/domain/entities/form_evaluation.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_level.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/warning_tracker.dart';

/// The live form score (0..100) and its colour: alignment (60%) + range of motion of
/// the last rep (25%) + tempo/consistency (15%). Missing parts are left out, never faked.
class FormScoreTracker {
  static const tau = 0.35; // form score smoothing time constant

  double score = 0;
  bool ready = false; // false = "Form not assessable"
  int state = 0; // 0 good, 1 warn, 2 bad (with hysteresis)
  double _lastTime = 0;
  double _lastAssessable = -99;

  /// [speed] = smoothed angular speed, [lastRom] / [lastConsistency] of the last rep
  void update(FormEvaluation ev, double t,
      {required double speed, required double maxSpeed, double? lastRom, double? lastConsistency}) {
    if (!(ev.assessable && ev.scores.isNotEmpty)) {
      if (t - _lastAssessable > 0.4) ready = false;
      return;
    }
    _lastAssessable = t;
    final mean = ev.scores.reduce((a, b) => a + b) / ev.scores.length;
    final align = 0.5 * mean + 0.5 * ev.scores.reduce(math.min); // worst check counts
    final ms = maxSpeed;
    final tempoNow = speed <= ms ? 1.0 : (1 - (speed - ms) / ms).clamp(0.0, 1.0).toDouble();
    var acc = 0.0, wsum = 0.0;
    void part(double? v, double wt) {
      if (v != null) {
        acc += v * wt;
        wsum += wt;
      }
    }

    part(align, 0.6);
    part(lastRom, 0.25);
    final lc = lastConsistency;
    part(lc == null ? tempoNow : (tempoNow + lc) / 2, 0.15);
    final target = 100 * acc / wsum;
    final dt = (t - _lastTime).clamp(0.0, 1.0).toDouble();
    _lastTime = t;
    score = ready ? score + (target - score) * (1 - math.exp(-dt / tau)) : target;
    if (!ready) state = 0;
    ready = true;
    state = _nextState(state, score);
  }

  static int _nextState(int s, double v) {
    const good = 80.0, bad = 55.0, hy = 5.0; // hysteresis: the colour doesn't flicker
    if (s == 0) return v < good - hy ? (v < bad ? 2 : 1) : 0;
    if (s == 1) return v >= good + hy ? 0 : (v < bad - hy ? 2 : 1);
    return v >= bad + hy ? (v >= good + hy ? 0 : 1) : 2;
  }

  /// colour of the depth bar, the rep progress and the form ring
  FormLevel level(double t, WarningTracker warnings) {
    if (!ready) return FormLevel.notAssessable;
    var st = state;
    if (warnings.shown.isNotEmpty) st = math.max(st, 1); // never emerald while a warning is up
    if (warnings.shown.any((m) => warnings.isSevere(m, t))) st = 2;
    return st == 0 ? FormLevel.good : (st == 1 ? FormLevel.warn : FormLevel.bad);
  }

  /// the word under the form ring
  String word(List<String> shown) {
    if (!ready) return 'NOT ASSESSABLE';
    if (score >= 90 && shown.isEmpty && state == 0) return 'FLAWLESS';
    return const ['GOOD', 'ADJUST', 'FAULT'][state.clamp(0, 2)];
  }
}
