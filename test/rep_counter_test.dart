import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_trainer/features/pose_coaching/data/datasources/exercise_local_data_source.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/body_landmark.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/services/rep_counter.dart';

/// a person filmed from the side with the right elbow bent to [elbowDeg]
PoseFrame sideCurl(double elbowDeg) {
  const shoulder = (300.0, 200.0), elbow = (300.0, 300.0), hip = (300.0, 400.0);
  final r = elbowDeg * math.pi / 180;
  // the forearm makes [elbowDeg] with the upper arm (which points up to the shoulder)
  final wrist = (elbow.$1 + 100 * math.sin(r), elbow.$2 - 100 * math.cos(r));
  final pts = <int, (double, double)>{
    11: (310, 200), 12: shoulder, 13: (310, 300), 14: elbow, 15: (310, 390), 16: wrist,
    23: (310, 400), 24: hip, 25: (310, 500), 26: (300, 500), 27: (310, 600), 28: (300, 600),
  };
  return PoseFrame(
    landmarks: [
      for (var id = 0; id < 33; id++)
        BodyLandmark(
          id: id,
          x: (pts[id] ?? (300.0, 150.0)).$1,
          y: (pts[id] ?? (300.0, 150.0)).$2,
          z: 0,
          likelihood: 0.99,
        ),
    ],
    timestamp: DateTime(2026),
  );
}

void main() {
  test('biceps curl: three full reps are counted and form a set', () {
    final curl = exercises.firstWhere((e) => e.name == 'Biceps Curl');
    final counter = RepCounter(curl);
    var t = 0.0;
    void hold(double deg, double secs) {
      for (var i = 0; i < secs * 30; i++) {
        counter.update(sideCurl(deg), t += 1 / 30);
      }
    }

    void move(double from, double to, double secs) {
      final n = (secs * 30).round();
      for (var i = 1; i <= n; i++) {
        counter.update(sideCurl(from + (to - from) * i / n), t += 1 / 30);
      }
    }

    hold(170, RepCounter.setupSeconds + 0.5); // the 5 s to get into position
    for (var rep = 0; rep < 3; rep++) {
      move(170, 40, 1);
      hold(40, 0.6); // the bottom must be held (holdSeconds) after the smoothing catches up
      move(40, 170, 1);
      hold(170, 1);
    }

    expect(counter.count, 3);
    expect(counter.setReps, 3);
    expect(counter.inSet, isTrue);
    expect(counter.repLabel, 'Good rep');
    expect(counter.fatigue, isNotNull);

    counter.endSet();
    expect(counter.lastSetReps, 3);
    counter.nextSet();
    expect(counter.setNumber, 2);
    expect(counter.setReps, 0);
  });

  test('biceps curl: reps from 30 to 130 deg of elbow flexion count (no locked-out arm needed)', () {
    final curl = exercises.firstWhere((e) => e.name == 'Biceps Curl');
    final counter = RepCounter(curl);
    var t = 0.0;
    void hold(double deg, double secs) {
      for (var i = 0; i < secs * 30; i++) {
        counter.update(sideCurl(deg), t += 1 / 30);
      }
    }

    void move(double from, double to, double secs) {
      final n = (secs * 30).round();
      for (var i = 1; i <= n; i++) {
        counter.update(sideCurl(from + (to - from) * i / n), t += 1 / 30);
      }
    }

    // elbow angle = 180 - flexion: 30 deg flexion = 150, 130 deg flexion = 50
    hold(150, RepCounter.setupSeconds + 0.5);
    for (var rep = 0; rep < 3; rep++) {
      move(150, 50, 1.5);
      hold(50, 0.6);
      move(50, 150, 2);
      hold(150, 1);
    }
    expect(counter.count, 3);
  });

  test('a half curl is reported as incomplete and not counted', () {
    final curl = exercises.firstWhere((e) => e.name == 'Biceps Curl');
    final counter = RepCounter(curl);
    var t = 0.0;
    for (var i = 0; i < (RepCounter.setupSeconds + 0.5) * 30; i++) {
      counter.update(sideCurl(170), t += 1 / 30);
    }
    for (final deg in [for (var i = 0; i <= 30; i++) 170 - 70 * i / 30, for (var i = 0; i <= 60; i++) 100 + 70 * i / 60]) {
      counter.update(sideCurl(deg.toDouble()), t += 1 / 30);
    }
    for (var i = 0; i < 30; i++) {
      counter.update(sideCurl(170), t += 1 / 30);
    }
    expect(counter.count, 0);
    expect(counter.repLabel, 'Incomplete rep');
  });

  test('no rep is counted in the first 5 s (get into position)', () {
    final curl = exercises.firstWhere((e) => e.name == 'Biceps Curl');
    final counter = RepCounter(curl);
    var t = 0.0;
    for (final deg in [
      for (var i = 0; i <= 30; i++) 170 - 130 * i / 30,
      for (var i = 0; i < 20; i++) 40,
      for (var i = 0; i <= 30; i++) 40 + 130 * i / 30,
    ]) {
      counter.update(sideCurl(deg.toDouble()), t += 1 / 30);
    }
    expect(t, lessThan(RepCounter.setupSeconds));
    expect(counter.count, 0);
    expect(counter.gateMsg, startsWith('Get in position'));
  });

  test('nobody in the picture: nothing is tracked', () {
    final counter = RepCounter(exercises.first);
    counter.update(PoseFrame.empty(DateTime(2026)), 1);
    expect(counter.tracking, isFalse);
    expect(counter.count, 0);
  });
}
