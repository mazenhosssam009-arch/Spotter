import 'dart:math' as math;

import 'package:ai_trainer/features/pose_coaching/data/datasources/exercise_local_data_source.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/body_landmark.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/rep_counter.dart';
import 'package:flutter_test/flutter_test.dart';

/// a person lying on a bench, filmed from the SIDE. [elbowDeg] = the angle at the
/// elbow of both arms (145 = arms extended, 92 = bar at the chest). The torso is
/// horizontal (shoulders and hips on the same line), so the lying gate is open.
/// The arms go UP from the shoulders: on a bench the bar is always above the elbows.
PoseFrame benchSide(double elbowDeg) {
  const shoulderR = (400.0, 300.0), shoulderL = (410.0, 305.0);
  const hipR = (180.0, 300.0), hipL = (190.0, 305.0);
  const elbowR = (400.0, 220.0), elbowL = (410.0, 225.0);
  // the forearm turns by (180 - elbowDeg) away from the upper arm
  final turn = (180 - elbowDeg) * math.pi / 180;
  final wristR = (
    elbowR.$1 + 100 * math.sin(turn),
    elbowR.$2 - 100 * math.cos(turn),
  );
  final wristL = (
    elbowL.$1 + 100 * math.sin(turn),
    elbowL.$2 - 100 * math.cos(turn),
  );
  return _pose(<int, (double, double)>{
    11: shoulderL, 12: shoulderR, 13: elbowL, 14: elbowR, 15: wristL, 16: wristR,
    23: hipL, 24: hipR, 25: (190.0, 400.0), 26: (180.0, 400.0),
    27: (190.0, 500.0), 28: (180.0, 500.0),
  });
}

/// The same person filmed from the HEAD / FOOT end of the bench, where the elbow
/// flare is visible. [elbowDeg] = elbow angle (145 top, 92 chest). [flareDeg] = the
/// angle at the shoulder between the torso and the upper arm (45-70 = elbows tucked,
/// 90+ = elbows straight out to the sides).
PoseFrame benchFront(double elbowDeg, {double flareDeg = 60}) =>
    _benchFront(elbowDeg, flareDeg: flareDeg, hipsUp: false);

/// The same press filmed from the head/foot end with the camera a little above the
/// bench: the hips are farther away (depth 80), so they appear ABOVE the shoulders in
/// the picture. A flare measured against the hip reads 120 degrees here even with the
/// elbows tucked at 60 (it used to reject every rep); the depth shows the real spread.
PoseFrame benchHeadEnd(double elbowDeg, {double flareDeg = 60}) =>
    _benchFront(elbowDeg, flareDeg: flareDeg, hipsUp: true);

PoseFrame _benchFront(double elbowDeg, {required double flareDeg, required bool hipsUp}) {
  const shoulders = [(300.0, 300.0), (400.0, 300.0)]; // left, right
  final hipY = hipsUp ? 240.0 : 360.0;
  final hips = [(300.0, hipY), (400.0, hipY)];
  final f = flareDeg * math.pi / 180;
  final e = elbowDeg * math.pi / 180;
  // upper arm: down and out to the side by [flareDeg]
  final ex = 120 * math.sin(f), ey = 120 * math.cos(f);
  // forearm: turn the ("elbow -> shoulder") direction by [elbowDeg]
  final ux = -math.sin(f), uy = -math.cos(f);
  final wx = ux * math.cos(e) - uy * math.sin(e);
  final wy = ux * math.sin(e) + uy * math.cos(e);
  // head/foot end from above: the bench runs away from the camera, so the hips are 80
  // units behind the shoulders and the elbow is 120*cos(flare) behind the shoulder.
  final elbowZ = hipsUp ? 120 * math.cos(f) : 0.0;
  final depth = <int, double>{
    if (hipsUp) ...{23: 80, 24: 80, 25: 80, 26: 80, 27: 80, 28: 80},
    if (hipsUp) ...{
      13: elbowZ, 14: elbowZ,
      15: elbowZ, 16: elbowZ,
    },
  };
  return _pose(<int, (double, double)>{
    11: shoulders[0], 12: shoulders[1],
    13: (shoulders[0].$1 + ex, shoulders[0].$2 + ey),
    14: (shoulders[1].$1 + ex, shoulders[1].$2 + ey),
    15: (shoulders[0].$1 + ex + 100 * wx, shoulders[0].$2 + ey + 100 * wy),
    16: (shoulders[1].$1 + ex + 100 * wx, shoulders[1].$2 + ey + 100 * wy),
    23: hips[0], 24: hips[1], 25: hips[0], 26: hips[1],
    27: (hips[0].$1, hipY + 80), 28: (hips[1].$1, hipY + 80),
  }, depth);
}

/// an upright person (shoulder press): the lying gate must keep the bench closed
PoseFrame upright(double elbowDeg) {
  const shoulderR = (400.0, 200.0), shoulderL = (300.0, 200.0);
  const elbowR = (400.0, 300.0), elbowL = (300.0, 300.0);
  final turn = (180 - elbowDeg) * math.pi / 180;
  return _pose(<int, (double, double)>{
    11: shoulderL, 12: shoulderR, 13: elbowL, 14: elbowR,
    15: (elbowL.$1 + 100 * math.sin(turn), elbowL.$2 + 100 * math.cos(turn)),
    16: (elbowR.$1 + 100 * math.sin(turn), elbowR.$2 + 100 * math.cos(turn)),
    23: (300.0, 400.0), 24: (400.0, 400.0), 25: (300.0, 500.0), 26: (400.0, 500.0),
    27: (300.0, 600.0), 28: (400.0, 600.0),
  });
}

/// a standing curl with only the head and upper body in frame: the hips are hidden, so
/// the lying check cannot tell that the person is not on a bench. The forearms hang
/// down (the wrist is below the elbow), which a bench press never does.
PoseFrame torsoCurl(double elbowDeg) {
  const shoulderR = (400.0, 200.0), shoulderL = (300.0, 200.0);
  const elbowR = (400.0, 300.0), elbowL = (300.0, 300.0);
  final turn = (180 - elbowDeg) * math.pi / 180;
  return _pose(<int, (double, double)>{
    0: (350.0, 150.0), // head seen: the "vertical head line" fallback of the lying check
    11: shoulderL, 12: shoulderR, 13: elbowL, 14: elbowR,
    15: (elbowL.$1 + 100 * math.sin(turn), elbowL.$2 + 100 * math.cos(turn)),
    16: (elbowR.$1 + 100 * math.sin(turn), elbowR.$2 + 100 * math.cos(turn)),
  });
}

/// the same curl filmed while sitting at a desk: the hips are seen but the torso is so
/// foreshortened that the lying check takes it for a head/foot-end bench view
PoseFrame seatedCurl(double elbowDeg) {
  const shoulderR = (400.0, 200.0), shoulderL = (300.0, 200.0);
  const elbowR = (400.0, 300.0), elbowL = (300.0, 300.0);
  final turn = (180 - elbowDeg) * math.pi / 180;
  return _pose(<int, (double, double)>{
    11: shoulderL, 12: shoulderR, 13: elbowL, 14: elbowR,
    15: (elbowL.$1 + 100 * math.sin(turn), elbowL.$2 + 100 * math.cos(turn)),
    16: (elbowR.$1 + 100 * math.sin(turn), elbowR.$2 + 100 * math.cos(turn)),
    23: (300.0, 250.0), 24: (400.0, 250.0), // foreshortened torso (ratio 0.5)
  });
}

PoseFrame _pose(Map<int, (double, double)> pts, [Map<int, double> depth = const {}]) =>
    PoseFrame(
      landmarks: [
        for (var id = 0; id < 33; id++)
          BodyLandmark(
            id: id,
            x: (pts[id] ?? (300.0, 150.0)).$1,
            y: (pts[id] ?? (300.0, 150.0)).$2,
            z: depth[id] ?? 0,
            likelihood: pts[id] == null ? 0.1 : 0.99,
          ),
      ],
      timestamp: DateTime(2026),
    );

/// drives a [RepCounter] with a pose for every frame (30 fps)
class _Sim {
  _Sim() : counter = RepCounter(exercises.firstWhere((e) => e.name == 'Bench Press'));
  final RepCounter counter;
  double t = 0;
  PoseFrame Function(double) pose = benchSide;

  void frame(double elbow) => counter.update(pose(elbow), t += 1 / 30);

  void hold(double elbow, double secs) {
    for (var i = 0; i < secs * 30; i++) {
      frame(elbow);
    }
  }

  void move(double from, double to, double secs) {
    final n = (secs * 30).round();
    for (var i = 1; i <= n; i++) {
      frame(from + (to - from) * i / n);
    }
  }

  /// one rep: down, brief hold, back up
  void rep({double bottom = 92, double down = 1.2, double up = 1.2, double holdHere = 0.5}) {
    move(145, bottom, down);
    hold(bottom, holdHere);
    move(bottom, 145, up);
    hold(145, 0.8);
  }

  void setup() => hold(145, RepCounter.setupSeconds + 0.5);
}

void main() {
  test('bench: three full reps from the side are counted and form a set', () {
    final s = _Sim()..setup();
    for (var i = 0; i < 3; i++) {
      s.rep();
    }

    expect(s.counter.count, 3);
    expect(s.counter.setReps, 3);
    expect(s.counter.inSet, isTrue);
    expect(s.counter.repLabel, 'Good rep');
  });

  test('bench: normal and fast tempos both count (touch-and-go)', () {
    for (final secs in [0.6, 0.8, 1.2, 2.5]) {
      final s = _Sim()..setup();
      s.rep(down: secs, up: secs, holdHere: 0.1);
      expect(s.counter.count, 1.0, reason: 'down/up $secs s');
    }
  });

  test('bench: continuous touch-and-go reps are all counted (no lost or extra reps)', () {
    final s = _Sim()..setup();
    // no pause at the top or the bottom: the smoothing must not merge them
    for (var r = 0; r < 4; r++) {
      s.move(145, 92, 0.7);
      s.move(92, 145, 0.7);
    }

    expect(s.counter.count, 4);
    expect(s.counter.repLabel, 'Good rep');
  });

  test('bench: a rep that does not reach the chest is incomplete and not counted', () {
    final s = _Sim()..setup();
    s.rep(bottom: 100); // per ~85, benchReach is 90

    expect(s.counter.count, 0);
    expect(s.counter.repLabel, 'Incomplete rep');
    expect(s.counter.repDetail, 'Lower to chest, lock out');
  });

  test('bench: a rep that just reaches the chest threshold counts', () {
    final s = _Sim()..setup();
    s.rep(bottom: 95); // per ~94

    expect(s.counter.count, 1);
    expect(s.counter.repLabel, 'Good rep');
  });

  test('bench: a rep with the elbows tucked in is counted (head/foot view)', () {
    final s = _Sim()
      ..pose = ((e) => benchFront(e, flareDeg: 60))
      ..setup();
    s.rep();

    expect(s.counter.count, 1);
    expect(s.counter.repLabel, 'Good rep');
  });

  test('bench: a moderate flare only warns and still counts the rep', () {
    final s = _Sim()
      ..pose = ((e) => benchFront(e, flareDeg: 95)) // past flareMax 80, below 100
      ..setup();
    s.move(145, 92, 1.2);
    s.hold(92, 0.8); // long enough for the warning to pass its debounce
    expect(s.counter.shown, contains('Elbows flared wide'));
    s.move(92, 145, 1.2);
    s.hold(145, 0.8);

    expect(s.counter.count, 1);
    expect(s.counter.repLabel, 'Good rep');
  });

  test('bench: elbows flared wide are not counted, even with a slow push up', () {
    final s = _Sim()
      ..pose = ((e) => benchFront(e, flareDeg: 120)) // far past the torso line
      ..setup();
    // slow push up: longer than the 0.6 s a warning is held, so only remembering the
    // worst flare of the rep itself can still reject it
    s.rep(up: 3);

    expect(s.counter.count, 0);
    expect(s.counter.repLabel, 'Rejected');
    expect(s.counter.repDetail, 'Elbows flared wide');
    expect(s.counter.setReps, 0);
  });

  test('bench: a head/foot view with the hips above the shoulders still counts', () {
    // the camera looks down the bench: the hips project ABOVE the shoulders, so a flare
    // measured against the hip reads ~180 on a perfectly tucked rep. Measuring against
    // the shoulder line keeps it at 60, so the rep must count.
    final s = _Sim()
      ..pose = ((e) => benchHeadEnd(e, flareDeg: 60))
      ..setup();
    s.rep();

    expect(s.counter.count, 1);
    expect(s.counter.repLabel, 'Good rep');
  });

  test('bench: a wide flare is still rejected in the head/foot view from above', () {
    final s = _Sim()
      ..pose = ((e) => benchHeadEnd(e, flareDeg: 120))
      ..setup();
    s.rep();

    expect(s.counter.count, 0);
    expect(s.counter.repLabel, 'Rejected');
    expect(s.counter.repDetail, 'Elbows flared wide');
  });

  test('bench: a single flare spike does not reject the rep', () {
    final s = _Sim()
      ..pose = ((e) => benchFront(e, flareDeg: 60))
      ..setup();
    s.move(145, 92, 1.2);
    s.pose = ((e) => benchFront(e, flareDeg: 130));
    s.frame(92); // one noisy frame at the bottom
    s.pose = ((e) => benchFront(e, flareDeg: 60));
    s.hold(92, 0.5);
    s.move(92, 145, 1.2);
    s.hold(145, 0.8);

    expect(s.counter.count, 1);
    expect(s.counter.repLabel, isNot('Rejected'));
  });

  test('bench: a flared rep does not spoil the next rep', () {
    final s = _Sim()
      ..pose = ((e) => benchFront(e, flareDeg: 120))
      ..setup();
    s.rep();
    expect(s.counter.count, 0);

    s.pose = ((e) => benchFront(e, flareDeg: 60));
    s.rep();
    expect(s.counter.count, 1);
    expect(s.counter.repLabel, 'Good rep');
  });

  test('bench: a standing curl with the hips out of frame is not counted', () {
    final s = _Sim()
      ..pose = torsoCurl
      ..setup();
    s.rep();

    expect(s.counter.count, 0);
    expect(s.counter.setReps, 0);
    expect(s.counter.gateMsg, 'Lie on the bench');
  });

  test('bench: a seated curl with a foreshortened torso is not counted', () {
    final s = _Sim()
      ..pose = seatedCurl
      ..setup();
    s.rep();

    expect(s.counter.count, 0);
    expect(s.counter.setReps, 0);
    expect(s.counter.gateMsg, 'Lie on the bench');
  });

  test('bench: a press while standing is blocked by the lying gate', () {
    final s = _Sim()
      ..pose = upright
      ..setup();
    s.rep();

    expect(s.counter.count, 0);
    expect(s.counter.gateMsg, 'Lie on the bench');
  });

  test('bench: no rep is counted in the first 5 s (get into position)', () {
    final s = _Sim();
    // a whole rep while the get-in-position countdown is still running
    s.rep();

    expect(s.t, lessThan(RepCounter.setupSeconds));
    expect(s.counter.count, 0);
    expect(s.counter.gateMsg, startsWith('Get in position'));
  });
}
