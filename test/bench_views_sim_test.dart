import 'dart:math' as math;

import 'package:ai_trainer/features/pose_coaching/data/datasources/exercise_local_data_source.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/body_landmark.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/rep_counter.dart';
import 'package:flutter_test/flutter_test.dart';

// A 3D bench press, projected through a camera, fed to the real RepCounter.
// World: x = toward the head, y = to the person's left, z = up. Metres.
// Bench technique (Rahmani 2009; Mausehund 2022): the forearm stays ~vertical, the upper arm
// turns from straight up (lockout) down to just below the torso line (bar on the chest).
// flare = shoulder abduction (angle between the torso and the upper arm, seen from above):
// ~45 deg at a normal grip, >75 at a wide grip (Fees 1998, cited in Noteboom et al. 2024).

typedef V3 = (double, double, double);

const upper = 0.30, fore = 0.27, halfShoulder = 0.20;

class Cam {
  Cam(this.pos, this.target, this.upHint);
  final V3 pos, target, upHint;
  static V3 sub(V3 a, V3 b) => (a.$1 - b.$1, a.$2 - b.$2, a.$3 - b.$3);
  static double dot(V3 a, V3 b) => a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;
  static V3 cross(V3 a, V3 b) =>
      (a.$2 * b.$3 - a.$3 * b.$2, a.$3 * b.$1 - a.$1 * b.$3, a.$1 * b.$2 - a.$2 * b.$1);
  static V3 norm(V3 a) {
    final l = math.sqrt(dot(a, a));
    return (a.$1 / l, a.$2 / l, a.$3 / l);
  }

  /// pixel position (x right, y down) and depth
  (double, double, double) project(V3 p) {
    final f = norm(sub(target, pos));
    final r = norm(cross(f, upHint));
    final u = cross(r, f);
    final d = sub(p, pos);
    final z = dot(d, f);
    return (400 + 900 * dot(d, r) / z, 400 - 900 * dot(d, u) / z, z);
  }
}

final cams = <String, Cam>{
  'side': Cam((0.15, -2.6, 0.35), (-0.15, 0, 0.1), (0, 0, 1)),
  'head end, bench height': Cam((2.2, 0, 0.45), (-0.2, 0, 0.1), (0, 0, 1)),
  'head end, from above 45': Cam((1.7, 0, 1.75), (-0.2, 0, 0.0), (0, 0, 1)),
  'straight above': Cam((-0.15, 0, 2.6), (-0.15, 0, 0), (1, 0, 0)),
  'foot end, bench height': Cam((-2.8, 0, 0.45), (-0.2, 0, 0.1), (0, 0, 1)),
  'foot end, floor': Cam((-2.8, 0, -0.35), (-0.2, 0, 0.1), (0, 0, 1)),
  'foot end, raised high': Cam((-2.4, 0, 1.6), (-0.2, 0, 0.0), (0, 0, 1)),
  'head end, floor': Cam((2.2, 0, -0.35), (-0.2, 0, 0.1), (0, 0, 1)),
  'head end, floor low': Cam((2.2, 0, -0.6), (-0.2, 0, 0.1), (0, 0, 1)),
  'head end, raised 0.6': Cam((2.1, 0, 0.8), (-0.2, 0, 0.1), (0, 0, 1)),
  'head end, raised 0.8': Cam((2.0, 0, 1.0), (-0.2, 0, 0.1), (0, 0, 1)),
};

/// landmarks of a lying bench presser. depth 0 = lockout, 1 = bar on the chest
Map<int, V3> benchBody(double depth, double flare) {
  final pts = <int, V3>{
    11: (0, halfShoulder, 0), 12: (0, -halfShoulder, 0),
    23: (-0.50, 0.15, 0), 24: (-0.50, -0.15, 0),
    25: (-0.95, 0.15, 0.05), 26: (-0.95, -0.15, 0.05),
    27: (-1.25, 0.20, -0.35), 28: (-1.25, -0.20, -0.35),
    0: (0.22, 0, 0.05), 7: (0.12, 0.08, 0.04), 8: (0.12, -0.08, 0.04),
  };
  // upper arm elevation: 90 (straight up) at lockout, -12 (just below the torso) on the chest
  final e = (90 - 102 * depth) * math.pi / 180;
  final a = flare * math.pi / 180;
  for (final (sh, el, wr, side) in [(11, 13, 15, 1.0), (12, 14, 16, -1.0)]) {
    final s = pts[sh]!;
    final h = upper * math.cos(e);
    final elbow = (s.$1 - h * math.cos(a), s.$2 + side * h * math.sin(a), s.$3 + upper * math.sin(e));
    pts[el] = elbow;
    pts[wr] = (elbow.$1, elbow.$2, elbow.$3 + fore); // forearm vertical
  }
  return pts;
}

/// a standing overhead (shoulder) press. depth 0 = arms overhead, 1 = bar at the shoulders
Map<int, V3> shoulderPress(double depth, {double flare = 80}) {
  // standing: the body axis is the world z; reuse the lying body turned upright
  final lying = benchBody(0, 0);
  final pts = <int, V3>{
    for (final e in lying.entries) e.key: (0.0, e.value.$2, 1.4 + e.value.$1), // x(head) -> z(up)
  };
  final a = flare * math.pi / 180;
  // upper arm from straight up (overhead) down to horizontal out to the side (bar at the chin)
  final e = (90 - 95 * depth) * math.pi / 180;
  for (final (sh, el, wr, side) in [(11, 13, 15, 1.0), (12, 14, 16, -1.0)]) {
    final s = pts[sh]!;
    final h = upper * math.cos(e);
    final elbow = (s.$1 + h * math.cos(a), s.$2 + side * h * math.sin(a), s.$3 + upper * math.sin(e));
    pts[el] = elbow;
    pts[wr] = (elbow.$1, elbow.$2, elbow.$3 + fore);
  }
  return pts;
}

final pressCams = <String, Cam>{
  'facing': Cam((2.5, 0, 1.3), (0, 0, 1.3), (0, 0, 1)),
  'side': Cam((0, -2.5, 1.3), (0, 0, 1.3), (0, 0, 1)),
};

/// the far side from the camera is seen less surely
PoseFrame frame(Map<int, V3> body, Cam cam, {bool farArmUnsure = false}) {
  final p = {for (final e in body.entries) e.key: cam.project(e.value)};
  final far = <int>{};
  if (farArmUnsure) {
    // the arm farther from the camera (larger depth)
    far.addAll(p[13]!.$3 > p[14]!.$3 ? [11, 13, 15] : [12, 14, 16]);
  }
  return PoseFrame(landmarks: [
    for (var id = 0; id < 33; id++)
      BodyLandmark(
        id: id,
        x: p[id]?.$1 ?? 400,
        y: p[id]?.$2 ?? 400,
        z: (p[id]?.$3 ?? 0) * 100,
        likelihood: p[id] == null ? 0.1 : (far.contains(id) ? 0.7 : 0.99),
      ),
  ], timestamp: DateTime(2026));
}

/// [reps] reps between [top] and [bottom] depth; returns (count, labels)
(double, Set<String>) run(PoseFrame Function(double depth) pose,
    {double top = 0, double bottom = 1, int reps = 5, bool lyingCheck = true}) {
  final c = RepCounter(exercises.firstWhere((e) => e.name == 'Bench Press'));
  if (!lyingCheck) c.toggleLyingCheck();
  final labels = <String>{};
  var t = 0.0;
  for (var i = 0; i < 6 * 30; i++) {
    c.update(pose(top), t += 1 / 30);
  }
  for (var r = 0; r < reps; r++) {
    for (var i = 0; i <= 36; i++) {
      c.update(pose(top + (bottom - top) * i / 36), t += 1 / 30);
    }
    for (var i = 0; i < 4; i++) {
      c.update(pose(bottom), t += 1 / 30);
    }
    for (var i = 36; i >= 0; i--) {
      c.update(pose(top + (bottom - top) * i / 36), t += 1 / 30);
    }
    for (var i = 0; i < 15; i++) {
      c.update(pose(top), t += 1 / 30);
    }
    if (c.repLabel.isNotEmpty) labels.add('${c.repLabel}${c.repDetail.isEmpty ? '' : ': ${c.repDetail}'}');
  }
  return (c.count, labels);
}

const cam = 'head end, bench height';

void main() {
  PoseFrame Function(double) bench(String view, double flare) =>
      (d) => frame(benchBody(d, flare), cams[view]!, farArmUnsure: view == 'side');

  group('side view', () {
    test('full reps count at normal grip widths (flare 45-75)', () {
      for (final f in [45.0, 60.0, 75.0]) {
        expect(run(bench('side', f)).$1, 5, reason: 'flare $f');
      }
    });
    test('half and 3/4 reps are not counted', () {
      for (final f in [45.0, 75.0]) {
        expect(run(bench('side', f), bottom: 0.5).$1, 0, reason: 'half, flare $f');
        expect(run(bench('side', f), bottom: 0.75).$1, 0, reason: '3/4, flare $f');
      }
    });
    test('still counts with the lying check OFF (the overhead-press guard leaves a bench press alone)', () {
      expect(run(bench('side', 60), lyingCheck: false).$1, 5);
    });
  });

  group('head end at bench height', () {
    test('full reps count from 35 to 85 deg of flare', () {
      for (final f in [35.0, 45.0, 60.0, 75.0, 85.0]) {
        expect(run(bench(cam, f)).$1, 5, reason: 'flare $f');
      }
    });
    test('half and 3/4 reps are not counted', () {
      expect(run(bench(cam, 60), bottom: 0.5).$1, 0);
      expect(run(bench(cam, 60), bottom: 0.75).$1, 0);
    });
    test('very tucked elbows (<= 30 deg) are rejected and named, every rep', () {
      for (final f in [10.0, 20.0, 30.0]) {
        final r = run(bench(cam, f));
        expect(r.$1, 0, reason: 'flare $f');
        expect(r.$2, {'Rejected: Elbows tucked in'}, reason: 'flare $f');
      }
    });
    test('elbows flared to 90+ deg are rejected, every rep (no counted/rejected flip)', () {
      for (final f in [90.0, 92.0, 95.0, 100.0]) {
        final r = run(bench(cam, f));
        expect(r.$1, 0, reason: 'flare $f');
        expect(r.$2, {'Rejected: Elbows flared wide'}, reason: 'flare $f');
      }
    });
    test('still counts with the lying check OFF', () {
      expect(run(bench(cam, 60), lyingCheck: false).$1, 5);
    });
  });

  group('foot end (the flare reads high there and cannot be judged)', () {
    for (final view in ['foot end, bench height', 'foot end, floor', 'foot end, raised high']) {
      test('$view: good reps are never rejected, lying check ON and OFF', () {
        for (final f in [45.0, 60.0, 75.0]) {
          expect(run(bench(view, f)).$1, 5, reason: 'flare $f');
          expect(run(bench(view, f), lyingCheck: false).$1, 5, reason: 'flare $f, lying off');
        }
      });
    }
    test('half reps are not counted', () {
      expect(run(bench('foot end, bench height', 60), bottom: 0.5).$1, 0);
    });
  });

  group('head end, phone on the floor (flare reads flattened near 90)', () {
    const v = 'head end, floor';
    test('full reps count from 30 to 85 deg; no 85 deg rep is rejected (90+ only warned here)', () {
      for (final f in [30.0, 45.0, 60.0, 75.0, 85.0]) {
        expect(run(bench(v, f)).$1, 5, reason: 'flare $f');
      }
    });
    test('very tucked (20 deg) is still rejected', () {
      expect(run(bench(v, 20)).$2, {'Rejected: Elbows tucked in'});
    });
    test('half and 3/4 reps are not counted, also with the phone flat on the floor', () {
      for (final view in [v, 'head end, floor low']) {
        for (final f in [30.0, 45.0, 75.0, 90.0]) {
          expect(run(bench(view, f), bottom: 0.5).$1, 0, reason: '$view half, flare $f');
          expect(run(bench(view, f), bottom: 0.75).$1, 0, reason: '$view 3/4, flare $f');
        }
      }
    });
    test('phone flat on the floor: full reps still count', () {
      for (final f in [30.0, 45.0, 75.0, 90.0]) {
        expect(run(bench('head end, floor low', f)).$1, 5, reason: 'flare $f');
      }
    });
  });

  group('head end, every phone height from the knee to 1.1 m: 85 counts, 90 is rejected', () {
    // (the reject limit follows the phone height; with one fixed limit a 90 deg flare was
    // counted at some heights and rejected at others)
    for (final z in [0.0, 0.2, 0.35, 0.55, 0.6, 0.65, 0.7, 0.9, 1.1]) {
      final c = Cam((2.2 - (z > 0.45 ? (z - 0.45) * 0.3 : 0), 0, z), (-0.2, 0, 0.1), (0, 0, 1));
      PoseFrame Function(double) at(double f) => (d) => frame(benchBody(d, f), c);
      test('phone at $z m', () {
        for (final f in [45.0, 75.0, 85.0]) {
          expect(run(at(f)).$1, 5, reason: 'flare $f');
        }
        for (final f in [90.0, 95.0]) {
          expect(run(at(f)).$2, {'Rejected: Elbows flared wide'}, reason: 'flare $f');
        }
        expect(run(at(60), bottom: 0.75).$1, 0, reason: '3/4 rep');
      });
    }
  });

  group('head end, phone raised above bench height (bar height gives the depth)', () {
    for (final v in ['head end, raised 0.6', 'head end, raised 0.8']) {
      test('$v: full reps count from 30 to 85 deg (45 deg was "incomplete" before)', () {
        for (final f in [30.0, 45.0, 60.0, 75.0, 85.0]) {
          expect(run(bench(v, f)).$1, 5, reason: 'flare $f');
        }
      });
      test('$v: half and 3/4 reps are not counted', () {
        for (final f in [20.0, 45.0, 75.0, 90.0]) {
          expect(run(bench(v, f), bottom: 0.5).$1, 0, reason: 'half, flare $f');
          expect(run(bench(v, f), bottom: 0.75).$1, 0, reason: '3/4, flare $f');
        }
      });
      test('$v: 90+ deg flare is still rejected', () {
        for (final f in [90.0, 95.0]) {
          expect(run(bench(v, f)).$2, {'Rejected: Elbows flared wide'}, reason: 'flare $f');
        }
      });
    }
  });

  group('elbow tip where the elbows cannot be judged', () {
    String? note(String view) {
      final c = RepCounter(exercises.firstWhere((e) => e.name == 'Bench Press'));
      var t = 0.0;
      for (var i = 0; i < 120; i++) {
        c.update(bench(view, 60)(0), t += 1 / 30);
      }
      return c.lastEval?.note;
    }

    test('side and foot end say where to put the phone; head end does not', () {
      expect(note('side'), 'Put the phone behind your head to check elbows');
      expect(note('foot end, bench height'), 'Put the phone behind your head to check elbows');
      expect(note('head end, bench height'), isNot('Put the phone behind your head to check elbows'));
    });
  });

  group('camera above the bench (top view)', () {
    for (final view in ['head end, from above 45', 'straight above']) {
      test('$view: no rep is counted or judged; the user is told where to put the phone', () {
        final c = RepCounter(exercises.firstWhere((e) => e.name == 'Bench Press'));
        var t = 0.0;
        for (var i = 0; i < 120; i++) {
          c.update(bench(view, 60)(0), t += 1 / 30);
        }
        expect(c.gateMsg, 'Put the phone at bench height');
        expect(run(bench(view, 60)).$1, 0);
        expect(run(bench(view, 95)).$2, isEmpty); // no random "flared" rejection
      });
    }
  });

  group('standing shoulder press is not a bench press', () {
    for (final view in pressCams.keys) {
      test('$view, lying check ON and OFF', () {
        expect(run((d) => frame(shoulderPress(d), pressCams[view]!)).$1, 0);
        expect(run((d) => frame(shoulderPress(d), pressCams[view]!), lyingCheck: false).$1, 0);
      });
    }
  });
}
