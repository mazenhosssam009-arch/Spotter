import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart' as mp;

import 'cv.dart';

/// false = ML Kit "base" model: clearly faster on most phones, good enough for lifting form.
/// true = "accurate" model (closest to mediapipe model_complexity=1) but it can halve the FPS.
const useAccurateModel = false;

// mp.solutions.pose.POSE_CONNECTIONS (ML Kit uses the same 33 landmark ids)
const poseConnections = [
  [0, 1], [1, 2], [2, 3], [3, 7], [0, 4], [4, 5], [5, 6], [6, 8], [9, 10],
  [11, 12], [11, 13], [13, 15], [15, 17], [15, 19], [15, 21], [17, 19],
  [12, 14], [14, 16], [16, 18], [16, 20], [16, 22], [18, 20], [11, 23],
  [12, 24], [23, 24], [23, 25], [24, 26], [25, 27], [26, 28], [27, 29],
  [28, 30], [29, 31], [30, 32], [27, 31], [28, 32],
];

class PoseDetector {
  PoseDetector({bool mode = false})
      : pose = mp.PoseDetector(
          options: mp.PoseDetectorOptions(
            mode: mode ? mp.PoseDetectionMode.single : mp.PoseDetectionMode.stream,
            model: useAccurateModel ? mp.PoseDetectionModel.accurate : mp.PoseDetectionModel.base,
          ),
        ),
        smoothLm = !mode;

  final mp.PoseDetector pose;
  // mediapipe smooth_landmarks=True (only used in video mode, like mediapipe)
  final bool smoothLm;
  final _smoother = _LandmarksSmoother();
  Map<mp.PoseLandmarkType, mp.PoseLandmark>? results;
  List<List<int>> lmList = [];

  Future<Frame> findPose(Frame img, {bool draw = true}) async {
    final poses = await pose.processImage(img.input);
    if (poses.isEmpty) {
      results = null;
      _smoother.reset();
    } else {
      // back to pixels of the full size picture
      final s = img.detectScale;
      var raw = poses.first.landmarks;
      if (img.swapLeftRight) raw = _swapSides(raw);
      final lms = s == 1
          ? raw
          : raw.map((type, l) => MapEntry(
              type,
              mp.PoseLandmark(type: type, x: l.x * s, y: l.y * s, z: l.z * s, likelihood: l.likelihood)));
      results = smoothLm ? _smoother.apply(lms, now()) : lms;
    }
    if (results != null && draw) _drawLandmarks(img);
    return img;
  }

  /// swaps every left/right landmark pair: eyes 1-3 <-> 4-6, then 7<->8, 9<->10 ... 31<->32
  static Map<mp.PoseLandmarkType, mp.PoseLandmark> _swapSides(
      Map<mp.PoseLandmarkType, mp.PoseLandmark> lms) {
    final v = mp.PoseLandmarkType.values;
    int swap(int i) {
      if (i == 0) return 0; // nose
      if (i <= 3) return i + 3; // left eye -> right eye
      if (i <= 6) return i - 3; // right eye -> left eye
      return i.isOdd ? i + 1 : i - 1; // 7<->8, 9<->10, ... 31<->32
    }
    return lms.map((type, l) {
      final t = v[swap(type.index)];
      return MapEntry(t, mp.PoseLandmark(type: t, x: l.x, y: l.y, z: l.z, likelihood: l.likelihood));
    });
  }

  // mpDraw.draw_landmarks: white connections, red points
  void _drawLandmarks(Frame img) {
    final lms = results!;
    mp.PoseLandmark? lm(int id) => lms[mp.PoseLandmarkType.values[id]];
    bool visible(mp.PoseLandmark? l) => l != null && l.likelihood > 0.5;
    for (final c in poseConnections) {
      final a = lm(c[0]), b = lm(c[1]);
      if (visible(a) && visible(b)) {
        img.line(a!.x.toInt(), a.y.toInt(), b!.x.toInt(), b.y.toInt(), white, 2);
      }
    }
    for (final l in lms.values) {
      if (visible(l)) img.circle(l.x.toInt(), l.y.toInt(), 3, red, filled);
    }
  }

  List<List<int>> findPosition(Frame img, {bool draw = true}) {
    lmList = [];
    final myPose = results;
    if (myPose != null) {
      for (final type in mp.PoseLandmarkType.values) {
        final lm = myPose[type];
        if (lm == null) continue;
        final cx = lm.x.toInt(), cy = lm.y.toInt();
        lmList.add([type.index, cx, cy]);
        if (draw) img.circle(cx, cy, 5, blue, filled);
      }
    }
    return lmList;
  }

  /// true when all these landmarks are really seen (like mediapipe drawing only
  /// landmarks with visibility > 0.5), not guessed because they are off screen
  bool isVisible(List<int> ids, {double minLikelihood = 0.5}) {
    final r = results;
    if (r == null) return false;
    return ids.every((id) => (r[mp.PoseLandmarkType.values[id]]?.likelihood ?? 0) >= minLikelihood);
  }

  double findAngle(Frame img, int p1, int p2, int p3, {bool draw = true}) {
    final x1 = lmList[p1][1], y1 = lmList[p1][2];
    final x2 = lmList[p2][1], y2 = lmList[p2][2];
    final x3 = lmList[p3][1], y3 = lmList[p3][2];
    var angle = (math.atan2(y3 - y2, x3 - x2) - math.atan2(y1 - y2, x1 - x2)) * 180 / math.pi;
    if (angle < 0) angle += 360;

    if (draw) {
      img.line(x1, y1, x2, y2, black, 3);
      img.line(x3, y3, x2, y2, black, 3);
      img.circle(x1, y1, 5, red, filled);
      img.circle(x1, y1, 10, red, 2);
      img.circle(x2, y2, 5, red, filled);
      img.circle(x2, y2, 10, red, 2);
      img.circle(x3, y3, 5, red, filled);
      img.circle(x3, y3, 10, red, 2);
      img.putText('${angle.toInt()}', x2 + 10, y2 - 30, 1.5, magenta, 2);
    }
    return angle;
  }

  void close() => pose.close();
}

/// mediapipe's LandmarksSmoothingCalculator with the pose settings
/// (pose_landmark_filtering.pbtxt): one euro filter, min_cutoff 0.05,
/// beta 80, derivate_cutoff 1, on pixel coordinates scaled by the body size.
class _LandmarksSmoother {
  final Map<mp.PoseLandmarkType, List<_OneEuroFilter>> _filters = {};

  void reset() => _filters.clear();

  Map<mp.PoseLandmarkType, mp.PoseLandmark> apply(
      Map<mp.PoseLandmarkType, mp.PoseLandmark> lms, double timestamp) {
    // object scale = average of the width and height of the landmarks box
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final l in lms.values) {
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

    final out = <mp.PoseLandmarkType, mp.PoseLandmark>{};
    lms.forEach((type, l) {
      final f = _filters.putIfAbsent(type, () => List.generate(3, (_) => _OneEuroFilter()));
      out[type] = mp.PoseLandmark(
        type: type,
        x: f[0].apply(timestamp, valueScale, l.x),
        y: f[1].apply(timestamp, valueScale, l.y),
        z: f[2].apply(timestamp, valueScale, l.z),
        likelihood: l.likelihood,
      );
    });
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