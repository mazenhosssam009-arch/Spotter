import 'dart:math' as math;

import 'package:ai_trainer/features/pose_coaching/data/datasources/exercise_local_data_source.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/body_landmark.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/bench_form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_geometry.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/posture_baseline.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/rep_counter.dart';
import 'package:flutter_test/flutter_test.dart';

PoseFrame _pose(Map<int, (double, double)> pts) => PoseFrame(
  landmarks: [
    for (var id = 0; id < 33; id++)
      BodyLandmark(
        id: id,
        x: (pts[id] ?? (300.0, 150.0)).$1,
        y: (pts[id] ?? (300.0, 150.0)).$2,
        z: 0,
        likelihood: pts[id] == null ? 0.1 : 0.99,
      ),
  ],
  timestamp: DateTime(2026),
);

/// A bench press seen from the head/foot end where only the RIGHT side of the body is
/// detected (the other hip/shoulder is hidden by the bench or the arm).
PoseFrame oneSideBench(double elbowDeg, {double flareDeg = 60}) {
  const shoulder = (400.0, 300.0);
  final f = flareDeg * math.pi / 180;
  final e = elbowDeg * math.pi / 180;
  final ex = 120 * math.sin(f), ey = 120 * math.cos(f);
  final ux = -math.sin(f), uy = -math.cos(f);
  final wx = ux * math.cos(e) - uy * math.sin(e);
  final wy = ux * math.sin(e) + uy * math.cos(e);
  final elbow = (shoulder.$1 + ex, shoulder.$2 + ey);
  return _pose(<int, (double, double)>{
    12: shoulder,
    14: elbow,
    16: (elbow.$1 + 100 * wx, elbow.$2 + 100 * wy),
    24: (400.0, 360.0),
    26: (400.0, 440.0),
    28: (400.0, 520.0),
  });
}

/// A level bar seen at an angle: the whole body is rolled [deg] degrees in the picture,
/// but the two wrists keep the same height relative to their own shoulders ("parallel
/// to the shoulder line"). [barLift] raises the right wrist against the left one.
PoseFrame rolledBench(double deg, {double barLift = 0}) {
  final r = deg * math.pi / 180;
  (double, double) rot((double, double) p) {
    const cx = 350.0, cy = 300.0;
    final dx = p.$1 - cx, dy = p.$2 - cy;
    return (
      cx + dx * math.cos(r) - dy * math.sin(r),
      cy + dx * math.sin(r) + dy * math.cos(r),
    );
  }

  return _pose(<int, (double, double)>{
    11: rot((300.0, 300.0)),
    12: rot((400.0, 300.0)),
    13: rot((300.0, 360.0)),
    14: rot((400.0, 360.0)),
    15: rot((300.0, 220.0)), // left wrist: level with its shoulder
    16: rot((400.0, 220.0 - barLift)), // right wrist: [barLift] px higher
    23: rot((300.0, 380.0)),
    24: rot((400.0, 380.0)),
  });
}

PoseFrame sideBenchArmsDown() => _pose(<int, (double, double)>{
  11: (410.0, 305.0),
  12: (400.0, 300.0),
  13: (410.0, 385.0),
  14: (400.0, 380.0),
  15: (410.0, 465.0),
  16: (400.0, 460.0),
  23: (190.0, 305.0),
  24: (180.0, 300.0),
  25: (190.0, 400.0),
  26: (180.0, 400.0),
  27: (190.0, 500.0),
  28: (180.0, 500.0),
});

void main() {
  test('bench: arms resting at the sides while lying do not say "Lie on the bench"', () {
    final counter = RepCounter(
      exercises.firstWhere((e) => e.name == 'Bench Press'),
    );
    var t = 0.0;
    for (var i = 0; i < 200; i++) {
      counter.update(sideBenchArmsDown(), t += 1 / 30);
    }

    expect(counter.gateMsg, isNot('Lie on the bench'));
  });

  test('bench: one hidden side does not fake an upright body (no "Lie on the bench")', () {
    final counter = RepCounter(
      exercises.firstWhere((e) => e.name == 'Bench Press'),
    );
    var t = 0.0;
    void frame(double elbow) =>
        counter.update(oneSideBench(elbow), t += 1 / 30);

    for (var i = 0; i < 200; i++) {
      frame(145); // get into position (5 s countdown)
    }
    expect(counter.gateMsg, isNot('Lie on the bench'));

    for (var i = 0; i < 40; i++) {
      frame(92); // down to the chest
    }
    for (var i = 0; i < 40; i++) {
      frame(145); // and back up
    }

    expect(counter.count, 1);
    expect(counter.repLabel, 'Good rep');
  });

  test('bench: a body rolled in the picture is not an uneven bar', () {
    final exercise = exercises.firstWhere((e) => e.name == 'Bench Press');
    final ev = const BenchFormCheck().check(
      FormCheckInput(
        pose: PoseGeometry(rolledBench(20)),
        exercise: exercise,
        per: 0,
        idle: true,
        front: true,
        baseline: PostureBaseline(),
      ),
    );

    expect(ev.warns, isNot(contains('Bar uneven')));
    expect(ev.named['Bar uneven'], 1.0);
  });

  test('bench: a bar that really tilts against the shoulders still warns', () {
    final exercise = exercises.firstWhere((e) => e.name == 'Bench Press');
    final ev = const BenchFormCheck().check(
      FormCheckInput(
        pose: PoseGeometry(rolledBench(20, barLift: 50)),
        exercise: exercise,
        per: 0,
        idle: true,
        front: true,
        baseline: PostureBaseline(),
      ),
    );

    expect(ev.warns, contains('Bar uneven'));
  });
}
