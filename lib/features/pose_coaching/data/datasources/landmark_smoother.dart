import 'dart:math' as math;

import 'package:ai_trainer/features/pose_coaching/domain/entities/body_landmark.dart';

/// mediapipe's LandmarksSmoothingCalculator with the pose settings
/// (pose_landmark_filtering.pbtxt): one euro filter, min_cutoff 0.05,
/// beta 80, derivate_cutoff 1, on pixel coordinates scaled by the body size.
class LandmarkSmoother {
  final Map<int, List<_OneEuroFilter>> _filters = {};

  void reset() => _filters.clear();

  List<BodyLandmark> apply(List<BodyLandmark> lms, double timestamp) {
    // object scale = average of the width and height of the landmarks box
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final l in lms) {
      minX = math.min(minX, l.x);
      maxX = math.max(maxX, l.x);
      minY = math.min(minY, l.y);
      maxY = math.max(maxY, l.y);
    }
    final objectScale = ((maxX - minX) + (maxY - minY)) / 2;
    if (objectScale < 1e-6) {
      reset();
      return lms;
    }
    final valueScale = 1 / objectScale;

    final out = <BodyLandmark>[];
    for (final l in lms) {
      final f = _filters.putIfAbsent(l.id, () => List.generate(3, (_) => _OneEuroFilter()));
      out.add(BodyLandmark(
        id: l.id,
        x: f[0].apply(timestamp, valueScale, l.x),
        y: f[1].apply(timestamp, valueScale, l.y),
        z: f[2].apply(timestamp, valueScale, l.z),
        likelihood: l.likelihood,
      ));
    }
    return out;
  }
}

/// port of mediapipe/util/filtering/one_euro_filter.cc
class _OneEuroFilter {
  static const minCutoff = 0.05, beta = 80.0, derivateCutoff = 1.0;
  double frequency = 30;
  double? lastTime;
  final _x = _LowPassFilter(), _dx = _LowPassFilter();

  double apply(double timestamp, double valueScale, double value) {
    if (lastTime != null) {
      if (timestamp <= lastTime!) return value;
      frequency = 1 / (timestamp - lastTime!);
    }
    lastTime = timestamp;
    final dvalue = _x.hasLast ? (value - _x.lastRaw) * valueScale * frequency : 0.0;
    final edvalue = _dx.apply(dvalue, _alpha(derivateCutoff));
    final cutoff = minCutoff + beta * edvalue.abs();
    return _x.apply(value, _alpha(cutoff));
  }

  double _alpha(double cutoff) {
    final te = 1 / frequency;
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / te);
  }
}

class _LowPassFilter {
  bool hasLast = false;
  double lastRaw = 0, stored = 0;

  double apply(double value, double alpha) {
    stored = hasLast ? alpha * value + (1 - alpha) * stored : value;
    lastRaw = value;
    hasLast = true;
    return stored;
  }
}
