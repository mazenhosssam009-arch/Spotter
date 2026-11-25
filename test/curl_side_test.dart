import 'dart:math' as math;

import 'package:ai_trainer/features/pose_coaching/data/datasources/exercise_local_data_source.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/body_landmark.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/rep_counter.dart';
import 'package:flutter_test/flutter_test.dart';

/// side-on curl, both arms working; the far (left) arm is hidden behind the body: ML Kit
/// guesses it with [farConf] and [noise] px of jitter. [flex] = elbow flexion from straight.
PoseFrame sideBoth(double flex, math.Random rnd, {double farConf = 0.7, double noise = 0}) {
  const sh = (300.0, 200.0), el = (300.0, 300.0);
  final r = (180 - flex) * math.pi / 180;
  final wr = (el.$1 + 100 * math.sin(r), el.$2 - 100 * math.cos(r));
  double j() => (rnd.nextDouble() * 2 - 1) * noise;
  final pts = <int, (double, double, double)>{
    12: (sh.$1, sh.$2, .99), 14: (el.$1, el.$2, .99), 16: (wr.$1, wr.$2, .99),
    11: (sh.$1 + 8 + j(), sh.$2 + j(), farConf), 13: (el.$1 + 8 + j(), el.$2 + j(), farConf),
    15: (wr.$1 + 8 + j(), wr.$2 + j(), farConf),
    24: (300, 400, .99), 23: (308, 400, .99), 26: (300, 500, .99), 25: (308, 500, .99),
    28: (300, 600, .99), 27: (308, 600, .99), 8: (290, 170, .99), 7: (298, 170, .5),
  };
  return PoseFrame(landmarks: [
    for (var id = 0; id < 33; id++)
      BodyLandmark(id: id, x: (pts[id]?.$1 ?? 300), y: (pts[id]?.$2 ?? 150), z: 0,
          likelihood: pts[id]?.$3 ?? 0.1),
  ], timestamp: DateTime(2026));
}

double run(int armMode, PoseFrame Function(double) pose, {double top = 0, double bottom = 130, int reps = 5}) {
  final c = RepCounter(exercises.firstWhere((e) => e.name == 'Biceps Curl'));
  c.setArmMode(armMode);
  var t = 0.0;
  for (var i = 0; i < 6 * 30; i++) {
    c.update(pose(top), t += 1 / 30);
  }
  for (var r = 0; r < reps; r++) {
    for (var i = 0; i <= 30; i++) {
      c.update(pose(top + (bottom - top) * i / 30), t += 1 / 30);
    }
    for (var i = 30; i >= 0; i--) {
      c.update(pose(top + (bottom - top) * i / 30), t += 1 / 30);
    }
    for (var i = 0; i < 12; i++) {
      c.update(pose(top), t += 1 / 30);
    }
  }
  return c.count;
}

void main() {
  final rnd = math.Random(3);
  test('curl from the side: full reps count (one arm, and both arms with the far arm hidden)', () {
    expect(run(0, (f) => sideBoth(f, rnd)), 5);
    expect(run(2, (f) => sideBoth(f, rnd)), 5);
    expect(run(2, (f) => sideBoth(f, rnd, noise: 20)), 5);
    expect(run(2, (f) => sideBoth(f, rnd, farConf: .99)), 5);
  });
  test('curl: a relaxed, slightly bent arm at the top still counts', () {
    expect(run(0, (f) => sideBoth(f, rnd), top: 25), 5);
    expect(run(0, (f) => sideBoth(f, rnd), top: 40), 5);
  });
  test('curl: half, partial and top-half reps are not counted (Pinto et al. 2012)', () {
    expect(run(0, (f) => sideBoth(f, rnd), bottom: 60), 0);
    expect(run(0, (f) => sideBoth(f, rnd), top: 50, bottom: 100), 0);
    expect(run(0, (f) => sideBoth(f, rnd), top: 60), 0);
  });
}
