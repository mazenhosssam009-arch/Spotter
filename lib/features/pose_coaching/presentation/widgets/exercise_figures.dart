import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:ai_trainer/core/theme/spotter_theme.dart';
import 'package:ai_trainer/core/widgets/spot_widgets.dart';

// A realistic, muscular trainer drawn in 3D from joint angles, so every pose is a handful of
// numbers, the poses can be animated by blending two of them, and the camera can turn 360 degrees
// around the trainer (front, side, back or a continuous spin).
//
// World axes: x = the way the trainer faces, y = down, z = his left / right.
// Camera yaw (degrees): 0 = side view, -90 (=270) = front, 90 = back, 180 = other side.
//
// Angles are in degrees, measured from "straight down" for limbs (0 = pointing down,
// 90 = pointing forward, 180 = pointing up) and from "straight up" for the torso
// (0 = upright, positive = leaning forward, -90 = lying with the head to the left).
//
// Arms:
//  - normal poses: upperArm / forearm angles (+ flare = sideways angle of the upper arm).
//  - lying (bench press): the wrists are put on a STRAIGHT VERTICAL line (the bar path) and the
//    elbows are solved with inverse kinematics. `bar` is the bar height (0 = touching the chest,
//    1 = locked out) and `flare` is how far the elbows are away from the body, in degrees.
//  - lockBar (deadlift): the bar stays on one vertical line over the mid foot while the body
//    hinges, the arms are solved with inverse kinematics and stay straight.

class FigPose {
  const FigPose({
    this.torso = 0,
    this.thigh = 0,
    this.shin = 0,
    this.upperArm = 0,
    this.forearm = 0,
    this.lying = false,
    this.bar = 0,
    this.flare = 0,
    this.lockBar = false,
  });

  final double torso; // hip -> shoulder, from vertical (forward +)
  final double thigh; // hip -> knee, from straight down (forward +)
  final double shin; // knee -> ankle, from straight down (backward = negative)
  final double upperArm; // shoulder -> elbow, from straight down
  final double forearm; // elbow -> wrist, from straight down
  final bool lying; // on a bench: the hip is fixed, the feet are on the floor
  final double bar; // lying only: bar height 0 (chest) .. 1 (lockout), straight vertical path
  final double flare; // degrees: lying = elbows away from the body, standing = arms out to the side
  final bool lockBar; // standing: wrists follow a straight vertical bar line (deadlift)

  static FigPose lerp(FigPose a, FigPose b, double t) {
    double l(double x, double y) => x + (y - x) * t;
    return FigPose(
      torso: l(a.torso, b.torso),
      thigh: l(a.thigh, b.thigh),
      shin: l(a.shin, b.shin),
      upperArm: l(a.upperArm, b.upperArm),
      forearm: l(a.forearm, b.forearm),
      lying: a.lying,
      bar: l(a.bar, b.bar),
      flare: l(a.flare, b.flare),
      lockBar: a.lockBar,
    );
  }
}

enum FigEquip { none, dumbbell, barbell }

/// the muscles that can glow while the trainer shows an exercise
enum FigMuscle { biceps, triceps, chest, back, quads, hams, glutes }

extension FigMuscleLabel on FigMuscle {
  String get label => switch (this) {
        FigMuscle.biceps => 'Biceps',
        FigMuscle.triceps => 'Triceps',
        FigMuscle.chest => 'Chest',
        FigMuscle.back => 'Back',
        FigMuscle.quads => 'Quads',
        FigMuscle.hams => 'Hamstrings',
        FigMuscle.glutes => 'Glutes',
      };
}

/// one picture of the guide: a pose, or two poses the trainer moves between
class FigStep {
  FigStep(this.from, [FigPose? to, this.equip = FigEquip.none, this.bad = false]) : to = to ?? from;
  final FigPose from, to;
  final FigEquip equip;
  final bool bad; // a mistake: the trainer wears red and gets a red cross
  bool get moves => !identical(from, to);

  /// the same picture with another weight (bar <-> dumbbells)
  FigStep withEquip(FigEquip e) => FigStep(from, to, e, bad);
}

/// the poses used by the guide
class Pz {
  Pz._();
  // --- biceps curl (elbows pinned close to the body) ---
  static const curlDown = FigPose(upperArm: 4, forearm: 4, flare: 5);
  static const curlUp = FigPose(upperArm: 4, forearm: 155, flare: 5);
  static const curlPin = FigPose(upperArm: 0, forearm: 90, flare: 5);
  static const curlSwing = FigPose(torso: -22, upperArm: 28, forearm: 140, flare: 5);
  // --- squat (arms forward for balance) ---
  static const squatStand = FigPose(upperArm: 88, forearm: 88, flare: -12);
  static const squatQuarter = FigPose(torso: 20, thigh: 40, shin: -15, upperArm: 88, forearm: 88, flare: -12);
  static const squatDown = FigPose(torso: 40, thigh: 85, shin: -35, upperArm: 88, forearm: 88, flare: -12);
  // --- deadlift (the bar goes straight up and down over the mid foot, arms stay straight) ---
  static const dlStand = FigPose(lockBar: true);
  static const dlHinge = FigPose(torso: 65, thigh: 18, shin: -8, lockBar: true);
  static const dlBottom = FigPose(torso: 65, thigh: 62, shin: -12, lockBar: true);
  // --- bench press (lying, head to the left): straight bar path, elbows ~45 degrees from the body.
  //     Change `flare` to taste (30 = tucked, 45 = standard, 80 = flared / a mistake) ---
  static const benchUp = FigPose(torso: -90, thigh: 110, shin: 20, lying: true, bar: 1, flare: 45);
  static const benchLow = FigPose(torso: -90, thigh: 110, shin: 20, lying: true, bar: 0, flare: 45);
  static const benchLowFlared = FigPose(torso: -90, thigh: 110, shin: 20, lying: true, bar: 0, flare: 80);
}

// ------------------------------------------------------------------------------------------
// tiny 3D vector + skeleton (forward kinematics + two-bone inverse kinematics)
// ------------------------------------------------------------------------------------------

class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x, y, z;
  _V3 operator +(_V3 o) => _V3(x + o.x, y + o.y, z + o.z);
  _V3 operator -(_V3 o) => _V3(x - o.x, y - o.y, z - o.z);
  _V3 operator *(double k) => _V3(x * k, y * k, z * k);
  _V3 operator /(double k) => _V3(x / k, y / k, z / k);
  double get len => math.sqrt(x * x + y * y + z * z);
  double dot(_V3 o) => x * o.x + y * o.y + z * o.z;
  _V3 cross(_V3 o) => _V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  _V3 get unit {
    final l = len;
    return l < 1e-9 ? this : this / l;
  }
}

class _Side {
  const _Side(this.hip, this.knee, this.ankle, this.shoulder, this.elbow, this.wrist);
  final _V3 hip, knee, ankle, shoulder, elbow, wrist;
}

class _Body {
  const _Body(this.hip, this.shoulder, this.head, this.headRot, this.sides);
  final _V3 hip, shoulder, head; // on the centre line (z = 0)
  final double headRot; // degrees, how far the head is tipped (face direction)
  final List<_Side> sides; // z = +, z = -
}

const _thigh = 1.0, _shin = 1.0, _torso = 1.3, _upperArm = 0.8, _foreArm = 0.75;
const _anchorX = 1.6, _ankleY = -0.14;

Offset _down(double deg) => Offset(math.sin(deg * math.pi / 180), math.cos(deg * math.pi / 180));
Offset _up(double deg) => Offset(math.sin(deg * math.pi / 180), -math.cos(deg * math.pi / 180));
double _cl(double v, double a, double b) => v < a ? a : (v > b ? b : v);

/// two-bone IK: shoulder s, wrist target w, the elbow is pushed towards `pole`
(_V3, _V3) _ik(_V3 s, _V3 w, double u, double f, _V3 pole) {
  final dv = w - s;
  final d = dv.len;
  final dir = d < 1e-6 ? const _V3(0, 1, 0) : dv / d;
  final dc = _cl(d, (u - f).abs() + 0.02, (u + f) * 0.995);
  final a = (u * u - f * f + dc * dc) / (2 * dc);
  final h = math.sqrt(math.max(0.0, u * u - a * a));
  var perp = pole - dir * pole.dot(dir);
  perp = perp.len < 1e-6 ? const _V3(0, 0, 1) : perp.unit;
  return (s + dir * a + perp * h, s + dir * dc);
}

_Body _fk3(FigPose p, {bool dumbbells = false}) {
  final double hx, hy;
  if (p.lying) {
    hx = 1.9;
    hy = -0.74;
  } else {
    // the feet stay where they are, the hip goes up and down with the knee angles
    final a = _down(p.thigh), b = _down(p.shin);
    hx = _anchorX - _thigh * a.dx - _shin * b.dx;
    hy = _ankleY - _thigh * a.dy - _shin * b.dy;
  }
  final hipXY = Offset(hx, hy);
  final shXY = hipXY + _up(p.torso) * _torso;
  final headXY = shXY + _up(p.lying ? p.torso : p.torso * 0.75) * 0.60;
  final fl = p.flare * math.pi / 180;
  final ua = p.upperArm * math.pi / 180, fa = p.forearm * math.pi / 180;

  final sides = <_Side>[];
  for (final sd in const [1.0, -1.0]) {
    final kXY = hipXY + _down(p.thigh) * _thigh;
    final aXY = kXY + _down(p.shin) * _shin;
    final hip = _V3(hx, hy, sd * 0.23);
    final knee = _V3(kXY.dx, kXY.dy, sd * 0.30);
    final ankle = _V3(aXY.dx, aXY.dy, sd * 0.32);
    final shJ = shXY - _up(p.torso) * 0.17; // the shoulder joint is below the top of the chest
    final sh = _V3(shJ.dx, shJ.dy, sd * 0.68);

    _V3 el, wr;
    if (p.lying) {
      // the wrists travel on a straight vertical line (the bar path)
      final w = _V3(sh.x + 0.38, -1.22 + (-2.20 + 1.22) * p.bar, sd * (dumbbells ? 0.60 : 0.78));
      final r = _ik(sh, w, _upperArm, _foreArm, _V3(math.cos(fl), 0.25, sd * math.sin(fl)));
      el = r.$1;
      wr = r.$2;
    } else if (p.lockBar) {
      final bx = _anchorX + 0.35;
      final dx = _cl(bx - sh.x, -1.4, 1.4);
      final reach = (_upperArm + _foreArm) * 0.985;
      final w = _V3(bx, sh.y + math.sqrt(reach * reach - dx * dx), sd * 0.68);
      final r = _ik(sh, w, _upperArm, _foreArm, _V3(-0.2, 0, sd));
      el = r.$1;
      wr = r.$2;
    } else {
      el = sh + _V3(math.sin(ua) * math.cos(fl), math.cos(ua) * math.cos(fl), sd * math.sin(fl)) * _upperArm;
      wr = el + _V3(math.sin(fa), math.cos(fa), 0) * _foreArm;
    }
    sides.add(_Side(hip, knee, ankle, sh, el, wr));
  }
  return _Body(
    _V3(hx, hy, 0),
    _V3(shXY.dx, shXY.dy, 0),
    _V3(headXY.dx, headXY.dy, 0),
    p.lying ? p.torso : p.torso * 0.35,
    sides,
  );
}

/// which way the "front" of a limb (knee cap, biceps, chest) points: perpendicular to the axis
_V3 _frontOf(_V3 a, _V3 b) {
  final ax = (b - a).unit;
  var fd = _V3(ax.y, -ax.x, 0);
  fd = fd - ax * fd.dot(ax);
  if (fd.len < 0.05) fd = const _V3(1, 0, 0) - ax * ax.x;
  return fd.unit;
}

// ------------------------------------------------------------------------------------------
// drawing helpers
// ------------------------------------------------------------------------------------------

/// convex hull (always the same winding), used to join two neighbouring cross-sections
List<Offset> _hull(List<Offset> pts) {
  final p = [...pts]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  double cr(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  final h = <Offset>[];
  for (final q in p) {
    while (h.length >= 2 && cr(h[h.length - 2], h.last, q) <= 0) {
      h.removeLast();
    }
    h.add(q);
  }
  final lo = h.length + 1;
  for (var i = p.length - 2; i >= 0; i--) {
    final q = p[i];
    while (h.length >= lo && cr(h[h.length - 2], h.last, q) <= 0) {
      h.removeLast();
    }
    h.add(q);
  }
  if (h.length > 1) h.removeLast();
  return h;
}

typedef _Prof = List<(double, double)>;

/// smooth interpolation of a (position along the limb 0..1, half width) profile
double _interp(_Prof prof, double t) {
  if (t <= prof.first.$1) return prof.first.$2;
  for (var i = 0; i < prof.length - 1; i++) {
    final a = prof[i], b = prof[i + 1];
    if (t <= b.$1) {
      var u = (t - a.$1) / (b.$1 - a.$1);
      u = (1 - math.cos(u * math.pi)) / 2;
      return a.$2 + (b.$2 - a.$2) * u;
    }
  }
  return prof.last.$2;
}

void _mv(Path p, Offset o) => p.moveTo(o.dx, o.dy);
void _ln(Path p, Offset o) => p.lineTo(o.dx, o.dy);
void _cb(Path p, Offset a, Offset b, Offset c) => p.cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);

// body shapes: half widths in character units. F = front, B = back, L = left/right (sideways)
const _Prof _thighF = [(0.0, 0.30), (0.3, 0.35), (0.65, 0.27), (1.0, 0.19)];
const _Prof _thighB = [(0.0, 0.31), (0.3, 0.30), (0.7, 0.22), (1.0, 0.18)];
const _Prof _thighL = [(0.0, 0.28), (0.3, 0.30), (0.65, 0.23), (1.0, 0.18)];
const _Prof _shinF = [(0.0, 0.15), (0.2, 0.14), (0.6, 0.11), (1.0, 0.08)];
const _Prof _shinB = [(0.0, 0.14), (0.3, 0.21), (0.62, 0.14), (1.0, 0.08)];
const _Prof _shinL = [(0.0, 0.13), (0.3, 0.16), (0.62, 0.12), (1.0, 0.07)];
const _Prof _torsoF = [(0.0, 0.22), (0.10, 0.33), (0.30, 0.39), (0.50, 0.33), (0.75, 0.28), (1.0, 0.29)];
const _Prof _torsoB = [(0.0, 0.22), (0.08, 0.32), (0.30, 0.36), (0.55, 0.29), (0.82, 0.28), (1.0, 0.31)];
const _Prof _torsoL = [(0.0, 0.44), (0.06, 0.64), (0.28, 0.66), (0.55, 0.50), (0.80, 0.43), (1.0, 0.45)];
const _Prof _shortsF = [(0.0, 0.30), (0.18, 0.35), (0.58, 0.37), (0.66, 0.35)];
const _Prof _shortsB = [(0.0, 0.32), (0.15, 0.37), (0.4, 0.35), (0.58, 0.31), (0.66, 0.29)];
const _Prof _shortsL = [(0.0, 0.46), (0.2, 0.52), (0.58, 0.55), (0.66, 0.55)];
const _Prof _neckF = [(0.0, 0.14), (1.0, 0.18)];
const _Prof _neckB = [(0.0, 0.15), (1.0, 0.22)];
const _Prof _neckL = [(0.0, 0.16), (1.0, 0.21)];
const _Prof _armF = [(0.0, 0.22), (0.3, 0.26), (0.55, 0.23), (0.8, 0.16), (1.0, 0.125)];
const _Prof _armB = [(0.0, 0.21), (0.35, 0.24), (0.7, 0.20), (1.0, 0.125)];
const _Prof _armL = [(0.0, 0.21), (0.35, 0.22), (0.8, 0.16), (1.0, 0.12)];
const _Prof _foreF = [(0.0, 0.16), (0.25, 0.20), (0.7, 0.125), (1.0, 0.08)];
const _Prof _foreB = [(0.0, 0.15), (0.25, 0.17), (0.7, 0.105), (1.0, 0.07)];
const _Prof _foreL = [(0.0, 0.15), (0.25, 0.18), (0.7, 0.115), (1.0, 0.075)];

// colours: rim, light, base, shade, deep
const List<Color> _skin = [Color(0xFFB5764F), Color(0xFFE8B08A), Color(0xFFD39870), Color(0xFFA8693F), Color(0xFF7C4A2C)];
const List<Color> _mint = [Color(0xFF1A9C70), Color(0xFF6FF0B8), Color(0xFF2FD39A), Color(0xFF1A9C70), Color(0xFF0F6B4C)];
const List<Color> _red = [Color(0xFF9E1B1B), Color(0xFFFF7A7A), Color(0xFFE04545), Color(0xFFB82A2A), Color(0xFF6E1212)];
const List<Color> _shortsCol = [Color(0xFF3A4660), Color(0xFF3B475C), Color(0xFF2A3342), Color(0xFF1D2431), Color(0xFF141A24)];

List<Color> _dim(List<Color> c, double k) => [for (final x in c) Color.lerp(x, Colors.black, k)!];

Paint _fillP(Color c, [double? a]) => Paint()
  ..isAntiAlias = true
  ..color = a == null ? c : c.withValues(alpha: _cl(a, 0, 1));

Paint _strokeP(Color c, double w, [double? a]) => Paint()
  ..isAntiAlias = true
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..color = a == null ? c : c.withValues(alpha: _cl(a, 0, 1));

Paint _shaderP(ui.Shader sh) => Paint()
  ..isAntiAlias = true
  ..shader = sh;

class _Item {
  _Item(this.d, this.f);
  final double d; // depth, bigger = closer to the camera
  final void Function() f;
}

class _FigDraw {
  _FigDraw(this.canvas, Size size, this.p, this.equip, this.bad, this.focus, this.glow, double yawDeg) {
    s = math.min(size.width / _w, size.height / _h);
    cx = size.width / 2;
    oy = (size.height - _h * s) / 2 + 4.5 * s;
    final y = yawDeg * math.pi / 180;
    cy = math.cos(y);
    sy = math.sin(y);
  }

  // the drawing area in character units: about 4.4 wide, y from -4.5 (top) to 0.35
  static const _w = 4.4, _h = 4.85, _pivot = 1.8;

  final Canvas canvas;
  final FigPose p;
  final FigEquip equip;
  final bool bad;
  final Set<FigMuscle> focus;
  final double glow; // 0 = no glow, 1 = full

  late final double s, cx, oy, cy, sy;

  // ---- camera: the world turns around the vertical axis through the trainer
  Offset pr(_V3 v) => Offset((v.x - _pivot) * cy + v.z * sy, v.y);
  Offset prv(_V3 v) => Offset(v.x * cy + v.z * sy, v.y);
  double dep(_V3 v) => -(v.x - _pivot) * sy + v.z * cy; // bigger = closer
  double depv(_V3 v) => -v.x * sy + v.z * cy;
  Offset m(Offset q) => Offset(cx + q.dx * s, oy + q.dy * s);
  Offset mv(_V3 v) => m(pr(v));

  double visF(_V3 f) => _cl(0.6 + depv(f) * 0.8, 0, 1); // a front muscle / line: visible?
  double visB(_V3 f) => _cl(0.6 - depv(f) * 0.8, 0, 1);
  double dimK(double d, double ref) => _cl((ref - d) * 1.1, 0, 0.3); // the far side is darker

  _V3 surf(_V3 a, _V3 b, double t, int side, double off) => a + (b - a) * t + _frontOf(a, b) * (side * off);

  double projAng(_V3 a, _V3 b) {
    final v = pr(b) - pr(a);
    return v.distance < 1e-3 ? 0 : math.atan2(v.dy, v.dx);
  }

  /// a shaded, rounded body part: a stack of projected elliptical cross-sections
  ({Path path, _V3 f}) tube(_V3 a, _V3 b, _Prof F, _Prof B, _Prof L, List<Color> cols,
      {bool capA = true, bool capB = true, double dark = 0}) {
    final d3 = b - a;
    final len = math.max(d3.len, 1e-4);
    final f = _frontOf(a, b);
    final l = (d3 / len).cross(f).unit;
    final path = Path();
    var wmax = 0.0;
    for (final e in [...F, ...B, ...L]) {
      wmax = math.max(wmax, e.$2);
    }

    // cross-sections along the limb (projected ellipses), then every neighbouring pair is joined
    // by a quad, so the part is one solid shape from any camera angle
    final secs = <(Offset, Offset, Offset)>[];
    void sec(double t, double k) {
      final tc = _cl(t, 0, 1);
      final fw = _interp(F, tc), bw = _interp(B, tc), lw = _interp(L, tc);
      final c = a + d3 * t + f * ((fw - bw) / 2);
      secs.add((pr(c), prv(f) * ((fw + bw) / 2 * k), prv(l) * (lw * k)));
    }

    const n = 20;
    if (capA) {
      final w = math.max((_interp(F, 0) + _interp(B, 0)) / 2, _interp(L, 0));
      for (var i = 4; i >= 1; i--) {
        final ph = math.pi / 2 * i / 5;
        sec(-math.sin(ph) * w / len, math.cos(ph));
      }
    }
    for (var i = 0; i <= n; i++) {
      sec(i / n, 1);
    }
    if (capB) {
      final w = math.max((_interp(F, 1) + _interp(B, 1)) / 2, _interp(L, 1));
      for (var i = 1; i <= 4; i++) {
        final ph = math.pi / 2 * i / 5;
        sec(1 + math.sin(ph) * w / len, math.cos(ph));
      }
    }

    // Every cross-section is a projected ellipse (a 16-point polygon). Each neighbouring pair is
    // joined by its CONVEX HULL, so every piece is a solid convex shape with exactly the same
    // winding. The union is painted once: no seams, holes or stripes at any camera angle.
    const seg = 16;
    final rings = <List<Offset>>[
      for (final (pc, uF, uL) in secs)
        [
          for (var j = 0; j < seg; j++)
            m(pc + uF * math.cos(2 * math.pi * j / seg) + uL * math.sin(2 * math.pi * j / seg))
        ]
    ];
    for (var i = 0; i < rings.length; i++) {
      final pts = i + 1 < rings.length ? [...rings[i], ...rings[i + 1]] : rings[i];
      path.addPolygon(_hull(pts), true);
    }

    final mid = pr(a + d3 * 0.5);
    const lv = Offset(0.78, -0.62); // light comes from the upper right of the screen
    final cc = dark > 0 ? _dim(cols, dark) : cols;
    final fill = _shaderP(ui.Gradient.linear(m(mid + lv * (wmax * 0.9)), m(mid - lv * (wmax * 0.9)), [cc[1], cc[2], cc[3]], const [0.0, 0.5, 1.0]));
    path.fillType = PathFillType.nonZero; // all pieces turn the same way, so this is a clean union
    canvas.drawPath(path, fill);
    return (path: path, f: f);
  }

  /// a soft round highlight / shadow, c is in projected character units
  void blob(Offset c, double rx, double ry, double ang, Color color, double alpha) {
    final cc = m(c);
    final a = _cl(alpha, 0, 1);
    canvas.save();
    canvas.translate(cc.dx, cc.dy);
    canvas.rotate(ang);
    canvas.scale(rx * s, ry * s);
    canvas.drawCircle(
      Offset.zero,
      1,
      _shaderP(ui.Gradient.radial(
          Offset.zero, 1, [color.withValues(alpha: a), color.withValues(alpha: 0)], const [0.0, 1.0])),
    );
    canvas.restore();
  }

  /// the mint glow of a working muscle, kept inside the body part
  void glowAt(_V3 c3, double rx, double ry, double ang, Path clip, double vis) {
    final g = glow * vis;
    if (g <= 0.03) return;
    canvas.save();
    canvas.clipPath(clip, doAntiAlias: true);
    final c = pr(c3);
    blob(c, rx * 1.5, ry * 1.5, ang, const Color(0xFF59EBAB), 0.9 * g);
    blob(c, rx * 0.7, ry * 0.7, ang, const Color(0xFFB5FFE0), 0.55 * g);
    canvas.restore();
  }

  /// thin line through some 3D points (muscle definition); vis fades it when it faces away
  void crv(List<_V3> pts, Color color, double w, double alpha, double vis) {
    final a = alpha * vis * 0.45;
    if (a < 0.03) return;
    final pa = Path();
    _mv(pa, mv(pts.first));
    for (final q in pts.skip(1)) {
      _ln(pa, mv(q));
    }
    canvas.drawPath(pa, _strokeP(color, w * s, a * 0.75));
  }

  /// the silhouette of an ellipsoid with the given 3D half axes
  void ellipsoid(_V3 c, List<(_V3, double)> axes, Paint paint) {
    var rx = 0.0, ry = 0.0;
    for (final a in axes) {
      final v = prv(a.$1) * a.$2;
      rx += v.dx * v.dx;
      ry += v.dy * v.dy;
    }
    canvas.drawOval(
        Rect.fromCenter(center: mv(c), width: 2 * math.sqrt(rx) * s, height: 2 * math.sqrt(ry) * s), paint);
  }

  // ---------------------------------------------------------------------------------------
  void draw() {
    final bd = _fk3(p, dumbbells: equip == FigEquip.dumbbell);
    final items = <_Item>[];
    final ref = dep(bd.hip);

    floor(bd);
    if (p.lying) bench(bd);

    for (final sd in bd.sides) {
      items.add(_Item((dep(sd.hip) + dep(sd.knee) + dep(sd.ankle)) / 3, () => leg(sd, ref)));
    }
    items.add(_Item(dep(bd.hip), () => torsoDraw(bd)));
    items.add(_Item(dep(bd.hip) + 0.3, () => shortsDraw(bd)));
    items.add(_Item(dep(bd.shoulder) + 0.1, () => neck(bd)));
    items.add(_Item(dep(bd.head) + 0.2, () => head(bd)));
    for (final sd in bd.sides) {
      items.add(_Item((dep(sd.shoulder) + dep(sd.elbow) + dep(sd.wrist)) / 3, () => arm(sd, ref)));
    }
    equipment(bd, items);

    items.sort((a, b) => a.d.compareTo(b.d));
    for (final it in items) {
      it.f();
    }
  }

  // ---- floor ring (turns with the trainer, the mint tick marks where he faces) + shadow
  void floor(_Body bd) {
    const r = 2.0, tilt = 0.14;
    final c = m(const Offset(0, 0.03));
    canvas.drawOval(Rect.fromCenter(center: c, width: 2 * r * s, height: 2 * r * tilt * s), _strokeP(Sp.line, 0.03 * s));
    for (var k = 0; k < 12; k++) {
      final phi = k * math.pi / 6;
      // world angle phi (0 = the way he faces) seen from the camera
      final yaw = math.atan2(sy, cy);
      final ang = phi - yaw;
      final q = m(Offset(r * math.cos(ang), 0.03 + r * tilt * math.sin(ang)));
      final near = (math.sin(ang) + 1) / 2;
      if (k == 0) {
        canvas.drawCircle(q, 0.06 * s, _fillP(Sp.mint, 0.55 + 0.45 * near));
      } else {
        canvas.drawCircle(q, 0.03 * s, _fillP(Sp.line, 0.5 + 0.5 * near));
      }
    }
    final sxw = ((bd.sides[0].ankle.x) + (p.lying ? 1.9 : bd.hip.x)) / 2 + 0.2;
    blob(Offset((sxw - _pivot) * cy, 0.03), 1.4 * cy.abs() + 0.8 * sy.abs() + 0.2, 0.16, 0, Colors.black, 0.4);
  }

  Rect rc(double cxp, double halfW, double y0, double y1) =>
      Rect.fromLTRB(m(Offset(cxp - halfW, y0)).dx, m(Offset(0, y0)).dy, m(Offset(cxp + halfW, y1)).dx, m(Offset(0, y1)).dy);

  void bench(_Body bd) {
    final top = bd.hip.y + 0.30;
    final bx0 = bd.hip.x - 1.95, bx1 = bd.hip.x + 0.5;
    const legc = Color(0xFF2A3230);
    for (final lx in [bx0 + 0.3, bx1 - 0.3]) {
      final pc = pr(_V3(lx, 0, 0)).dx;
      canvas.drawRRect(RRect.fromRectXY(rc(pc, 0.06 * cy.abs() + 0.06 * sy.abs(), top + 0.1, 0), 2, 2), _fillP(legc));
      canvas.drawRRect(
          RRect.fromRectXY(rc(pc, 0.06 * cy.abs() + 0.28 * sy.abs(), -0.05, 0.03), 2, 2), _fillP(legc));
    }
    final pc = pr(_V3((bx0 + bx1) / 2, 0, 0)).dx;
    final pad = rc(pc, (bx1 - bx0) / 2 * cy.abs() + 0.36 * sy.abs(), top, top + 0.2);
    canvas.drawRRect(
      RRect.fromRectXY(pad, 0.09 * s, 0.09 * s),
      _shaderP(ui.Gradient.linear(Offset(0, pad.top), Offset(0, pad.bottom),
          const [Color(0xFF4A5753), Color(0xFF232B29)], const [0.0, 1.0])),
    );
  }

  // ---- legs: lower leg, shoe, thigh
  void leg(_Side sd, double ref) {
    final dk = dimK((dep(sd.hip) + dep(sd.knee) + dep(sd.ankle)) / 3, ref);
    final shin = tube(sd.knee, sd.ankle, _shinF, _shinB, _shinL, _skin, dark: dk);
    final vs = visF(shin.f), vb = visB(shin.f);
    crv([surf(sd.knee, sd.ankle, 0.12, -1, 0.06), surf(sd.knee, sd.ankle, 0.35, -1, 0.09), surf(sd.knee, sd.ankle, 0.6, -1, 0.02)],
        _skin[4], 0.018, 0.35, vb);
    crv([surf(sd.knee, sd.ankle, 0.15, 1, 0.12), surf(sd.knee, sd.ankle, 0.55, 1, 0.08)], _skin[1], 0.03, 0.35, vs);
    shoe(sd.ankle, dk);

    final th = tube(sd.hip, sd.knee, _thighF, _thighB, _thighL, _skin, capA: false, dark: dk);
    final tf = visF(th.f), tb = visB(th.f);
    crv([surf(sd.hip, sd.knee, 0.35, 1, 0.02), surf(sd.hip, sd.knee, 0.6, 1, 0.1), surf(sd.hip, sd.knee, 0.9, 1, 0.08)],
        _skin[4], 0.018, 0.35, tf);
    crv([surf(sd.hip, sd.knee, 0.25, 1, 0.17), surf(sd.hip, sd.knee, 0.5, 1, 0.2), surf(sd.hip, sd.knee, 0.75, 1, 0.13)],
        _skin[1], 0.035, 0.45, tf);
    crv([surf(sd.hip, sd.knee, 0.45, -1, 0.04), surf(sd.hip, sd.knee, 0.8, -1, 0.03)], _skin[4], 0.015, 0.3, tb);
    final ang = projAng(sd.hip, sd.knee);
    if (focus.contains(FigMuscle.quads)) glowAt(surf(sd.hip, sd.knee, 0.5, 1, 0.12), 0.2, 0.34, ang, th.path, tf);
    if (focus.contains(FigMuscle.hams)) glowAt(surf(sd.hip, sd.knee, 0.5, -1, 0.1), 0.2, 0.34, ang, th.path, tb);
  }

  void shoe(_V3 ankle, double dk) {
    final ax = pr(ankle).dx, ay = ankle.y + 0.14; // the ankle is a little above the floor
    final accent = bad ? const Color(0xFFFF6A6A) : const Color(0xFF59EBAB);
    final k = cy; // the length of the shoe shrinks when we look at it from the front
    final w = 0.17 * sy.abs();
    Offset q(double x, double y) => m(Offset(ax + x * k, ay + y));
    final pa = Path();
    _mv(pa, q(-0.22, -0.27));
    _cb(pa, q(-0.05, -0.33), q(0.13, -0.30), q(0.22, -0.20));
    _cb(pa, q(0.38, -0.13), q(0.58, -0.13), q(0.66, -0.05));
    _ln(pa, q(0.68, 0.0));
    _ln(pa, q(-0.26, 0.0));
    _cb(pa, q(-0.30, -0.10), q(-0.28, -0.20), q(-0.22, -0.27));
    pa.close();
    final white = [Color.lerp(const Color(0xFFFFFFFF), Colors.black, dk)!, Color.lerp(const Color(0xFFD9DEDC), Colors.black, dk)!];
    final sh = _shaderP(ui.Gradient.linear(Offset(0, q(0, -0.3).dy), Offset(0, q(0, 0).dy), white, const [0.0, 1.0]));
    canvas.drawPath(pa, sh);
    // when seen from the front or back, the shoe is a rounded block as wide as the foot
    canvas.drawRRect(
        RRect.fromRectXY(rc(ax + 0.2 * k, w + 0.02, ay - 0.27, ay), 4, 4), sh);
    // sole
    final x0 = math.min(-0.27 * k, 0.69 * k), x1 = math.max(-0.27 * k, 0.69 * k);
    canvas.drawRRect(
        RRect.fromRectXY(Rect.fromLTRB(m(Offset(ax + x0 - w, ay)).dx, q(0, -0.06).dy, m(Offset(ax + x1 + w, ay)).dx, q(0, 0.015).dy), 4, 4),
        _fillP(bad ? const Color(0xFFFF6A6A) : const Color(0xFF5CE0A8)));
    // accent stripe
    final st = Path();
    _mv(st, q(0.15, -0.17));
    st.quadraticBezierTo(q(0.35, -0.10).dx, q(0.35, -0.10).dy, q(0.55, -0.09).dx, q(0.55, -0.09).dy);
    canvas.drawPath(st, _strokeP(accent, 0.03 * s, 0.9 * cy.abs()));
  }

  // ---- torso (built from the shoulder down, so "front" is the chest)
  void torsoDraw(_Body bd) {
    final shirt = bad ? _red : _mint;
    final tor = tube(bd.shoulder, bd.hip, _torsoF, _torsoB, _torsoL, shirt, capB: false);
    final vf = visF(tor.f), vb = visB(tor.f);
    final a = bd.shoulder, b = bd.hip;
    crv([surf(a, b, 0.26, 1, 0.02), surf(a, b, 0.34, 1, 0.25), surf(a, b, 0.40, 1, 0.16)], shirt[4], 0.028, 0.5, vf);
    crv([surf(a, b, 0.18, 1, 0.12), surf(a, b, 0.3, 1, 0.27)], shirt[1], 0.05, 0.35, vf);
    crv([surf(a, b, 0.22, -1, 0.1), surf(a, b, 0.42, -1, 0.22), surf(a, b, 0.62, -1, 0.13)], shirt[4], 0.03, 0.45, vb);
    final ang = projAng(a, b);
    if (focus.contains(FigMuscle.chest)) glowAt(surf(a, b, 0.3, 1, 0.14), 0.26, 0.26, ang, tor.path, vf);
    if (focus.contains(FigMuscle.back)) glowAt(surf(a, b, 0.5, -1, 0.12), 0.22, 0.4, ang, tor.path, vb);
  }

  // ---- shorts (cover the lower edge of the shirt and the top of the thighs)
  void shortsDraw(_Body bd) {
    final kneeC = _V3(bd.sides[0].knee.x, bd.sides[0].knee.y, 0);
    final end = bd.hip + (kneeC - bd.hip) * 0.62;
    final start = bd.hip + (bd.shoulder - bd.hip) * 0.12;
    // pelvis: a round block at the hip joint that closes the gap where the torso and the
    // thighs meet at an angle (squat, deadlift, bench)
    final pv = bd.hip + (bd.shoulder - bd.hip) * 0.04;
    final pc0 = mv(pv);
    ellipsoid(pv, const [(_V3(1, 0, 0), 0.36), (_V3(0, 1, 0), 0.36), (_V3(0, 0, 1), 0.52)],
        _shaderP(ui.Gradient.linear(Offset(pc0.dx, pc0.dy - 0.36 * s), Offset(pc0.dx, pc0.dy + 0.36 * s),
            [_shortsCol[1], _shortsCol[2], _shortsCol[3]], const [0.0, 0.5, 1.0])));
    final r = tube(start, end, _shortsF, _shortsB, _shortsL, _shortsCol, capA: false, capB: false);
    const trim = Color(0xFF5F6F8A);
    final f = r.f;
    final l = (end - start).unit.cross(f).unit;
    final vf = visF(f), vb = visB(f);
    // waistband and hem: arcs around the body (front half / back half)
    List<_V3> arc(_V3 c, double rF, double rL, double a0, double a1) =>
        [for (var i = 0; i <= 6; i++) c + f * (rF * math.cos(a0 + (a1 - a0) * i / 6)) + l * (rL * math.sin(a0 + (a1 - a0) * i / 6))];
    crv(arc(start, 0.34, 0.44, -math.pi / 2, math.pi / 2), trim, 0.025, 0.8, vf);
    crv(arc(start, 0.45, 0.44, math.pi / 2, 3 * math.pi / 2), trim, 0.025, 0.8, vb);
    crv(arc(end, 0.41, 0.50, -math.pi / 2, math.pi / 2), trim, 0.02, 0.9, vf);
    crv(arc(end, 0.35, 0.50, math.pi / 2, 3 * math.pi / 2), trim, 0.02, 0.9, vb);
    if (focus.contains(FigMuscle.glutes)) {
      for (final sd in bd.sides) {
        glowAt(surf(sd.hip, sd.knee, 0.12, -1, 0.2), 0.3, 0.3, projAng(sd.hip, sd.knee), r.path, vb);
      }
    }
  }

  void neck(_Body bd) {
    final d = (bd.shoulder - bd.head).unit;
    tube(bd.head + d * 0.18, bd.shoulder - d * 0.05, _neckF, _neckB, _neckL, _skin, capA: false, capB: false);
  }

  // ---- head: an ellipsoid with a hair cap, a face when it looks at us and the original
  //      profile (nose, chin, beard) when we see it from the side
  void head(_Body bd) {
    const hs = 0.70; // head height in character units
    final rot = bd.headRot * math.pi / 180;
    final fwd = _V3(math.cos(rot), math.sin(rot), 0);
    final upH = _V3(math.sin(rot), -math.cos(rot), 0);
    const lat = _V3(0, 0, 1);
    final hc = bd.head;
    final fv = depv(fwd); // > 0: the face is turned to the camera
    final front = _cl(fv, 0, 1), back = _cl(-fv, 0, 1);
    final profA = _cl((cy.abs() - 0.55) / 0.35, 0, 1);
    final cc = mv(hc);

    // skull
    final skinShader = _shaderP(ui.Gradient.linear(
        Offset(cc.dx + 0.4 * hs * s, cc.dy), Offset(cc.dx - 0.4 * hs * s, cc.dy),
        [_skin[2], _skin[1], _skin[2], _skin[3]], const [0.0, 0.25, 0.65, 1.0]));
    ellipsoid(hc, [(fwd, 0.44 * hs), (upH, 0.52 * hs), (lat, 0.36 * hs)], skinShader);

    // ears (only the ones on the side of the head we can see)
    for (final sd in const [1.0, -1.0]) {
      final e3 = hc + lat * (sd * 0.35 * hs) - fwd * (0.06 * hs);
      if (dep(e3) - dep(hc) > -0.1) {
        canvas.drawOval(Rect.fromCenter(center: mv(e3), width: 0.09 * hs * s, height: 0.17 * hs * s),
            _fillP(_skin[3], 1 - profA * 0.6));
      }
    }

    // hair cap: only the top from the front, more of it from the back
    const hairCol = Color(0xFF2B1D14);
    final hairA = 1 - profA;
    if (hairA > 0.02) {
      ellipsoid(
        hc + upH * (hs * (0.36 - 0.36 * back)) - fwd * (0.04 * hs),
        [(fwd, 0.47 * hs), (lat, 0.39 * hs), (upH, hs * (0.15 + 0.32 * back))],
        _fillP(hairCol, hairA),
      );
    }

    // face (front view)
    final fa = front * (1 - profA * 0.9);
    if (fa > 0.04) {
      for (final sd in const [1.0, -1.0]) {
        final e = mv(hc + fwd * (0.30 * hs) + upH * (0.075 * hs) + lat * (sd * 0.17 * hs));
        canvas.drawOval(Rect.fromCenter(center: e, width: 0.15 * hs * s, height: 0.085 * hs * s),
            _fillP(const Color(0xFFF4F1EE), fa));
        canvas.drawCircle(e, 0.036 * hs * s, _fillP(const Color(0xFF1B120C), fa));
        canvas.drawLine(
            mv(hc + fwd * (0.31 * hs) + upH * (0.16 * hs) + lat * (sd * 0.09 * hs)),
            mv(hc + fwd * (0.31 * hs) + upH * (0.17 * hs) + lat * (sd * 0.26 * hs)),
            _strokeP(hairCol, 0.03 * hs * s, fa));
      }
      ellipsoid(hc + fwd * (0.15 * hs) - upH * (0.30 * hs), [(fwd, 0.2 * hs), (upH, 0.2 * hs), (lat, 0.3 * hs)],
          _fillP(hairCol, 0.14 * fa));
      canvas.drawLine(mv(hc + fwd * (0.33 * hs) - upH * (0.23 * hs) - lat * (0.08 * hs)),
          mv(hc + fwd * (0.33 * hs) - upH * (0.23 * hs) + lat * (0.08 * hs)), _strokeP(const Color(0xFF8F5A3C), 0.026 * hs * s, fa));
      canvas.drawCircle(mv(hc + fwd * (0.42 * hs) - upH * (0.02 * hs)), 0.05 * hs * s, _fillP(_skin[3], 0.6 * fa));
    }

    // profile (side view): the original detailed side picture, mirrored when he faces left
    if (profA > 0.02) {
      canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: profA));
      final flip = cy >= 0 ? 1.0 : -1.0;
      final xsq = 0.85 + 0.15 * cy.abs();
      final cr = math.cos(rot), sr = math.sin(rot);
      Offset pt(double x, double y) {
        final xr = x * cr - y * sr;
        final yr = x * sr + y * cr;
        return Offset(cc.dx + flip * xr * hs * s * xsq, cc.dy + yr * hs * s);
      }

      final pa = Path();
      _mv(pa, pt(-0.04, -0.50));
      _cb(pa, pt(0.14, -0.50), pt(0.30, -0.42), pt(0.34, -0.26)); // forehead
      _cb(pa, pt(0.35, -0.20), pt(0.34, -0.15), pt(0.33, -0.12)); // brow -> nose bridge
      _cb(pa, pt(0.36, -0.05), pt(0.42, 0.04), pt(0.45, 0.08)); // nose
      _cb(pa, pt(0.45, 0.11), pt(0.40, 0.12), pt(0.34, 0.12)); // under the nose
      _cb(pa, pt(0.35, 0.15), pt(0.36, 0.17), pt(0.35, 0.19)); // upper lip
      _cb(pa, pt(0.34, 0.21), pt(0.33, 0.22), pt(0.34, 0.24)); // mouth
      _cb(pa, pt(0.35, 0.27), pt(0.34, 0.29), pt(0.31, 0.31)); // lower lip
      _cb(pa, pt(0.30, 0.34), pt(0.34, 0.38), pt(0.35, 0.42)); // chin
      _cb(pa, pt(0.34, 0.49), pt(0.26, 0.54), pt(0.15, 0.53)); // chin bottom
      _cb(pa, pt(0.04, 0.52), pt(-0.10, 0.46), pt(-0.18, 0.34)); // jaw line
      _cb(pa, pt(-0.28, 0.22), pt(-0.40, 0.16), pt(-0.44, 0.0)); // back of the head
      _cb(pa, pt(-0.48, -0.28), pt(-0.30, -0.50), pt(-0.04, -0.50)); // crown
      pa.close();
      canvas.drawPath(pa, skinShader);

      final jaw = Path();
      _mv(jaw, pt(-0.18, 0.34));
      _cb(jaw, pt(-0.05, 0.46), pt(0.15, 0.52), pt(0.30, 0.5));
      _ln(jaw, pt(0.30, 0.38));
      _cb(jaw, pt(0.12, 0.42), pt(-0.05, 0.36), pt(-0.18, 0.2));
      jaw.close();
      canvas.drawPath(jaw, _fillP(const Color(0xFF7C4A2C), 0.32));

      final bdp = Path();
      _mv(bdp, pt(0.34, 0.26));
      _cb(bdp, pt(0.34, 0.45), pt(0.22, 0.53), pt(0.08, 0.50));
      _cb(bdp, pt(-0.06, 0.46), pt(-0.14, 0.38), pt(-0.18, 0.2));
      _ln(bdp, pt(-0.05, 0.12));
      _cb(bdp, pt(0.05, 0.28), pt(0.2, 0.3), pt(0.30, 0.22));
      bdp.close();
      canvas.drawPath(bdp, _fillP(hairCol, 0.4));

      final hr = Path();
      _mv(hr, pt(0.33, -0.27));
      _cb(hr, pt(0.30, -0.44), pt(0.14, -0.55), pt(-0.06, -0.54));
      _cb(hr, pt(-0.32, -0.54), pt(-0.50, -0.34), pt(-0.46, -0.04));
      _cb(hr, pt(-0.44, 0.06), pt(-0.40, 0.14), pt(-0.36, 0.17));
      _ln(hr, pt(-0.27, 0.02));
      _cb(hr, pt(-0.22, -0.10), pt(-0.12, -0.14), pt(0.0, -0.17));
      _cb(hr, pt(0.16, -0.20), pt(0.26, -0.22), pt(0.33, -0.27));
      hr.close();
      canvas.drawPath(
          hr,
          _shaderP(ui.Gradient.linear(
              pt(0, -0.55), pt(-0.3, 0.1), const [Color(0xFF4A3426), Color(0xFF21150E)], const [0.0, 1.0])));

      final e = pt(-0.14, 0.02);
      canvas.drawOval(Rect.fromLTWH(e.dx - 0.046 * hs * s, e.dy - 0.09 * hs * s, 0.092 * hs * s, 0.18 * hs * s),
          _fillP(_skin[3]));
      final ey = pt(0.21, -0.075);
      canvas.drawOval(Rect.fromLTWH(ey.dx - 0.035 * hs * s, ey.dy - 0.02 * hs * s, 0.07 * hs * s, 0.04 * hs * s),
          _fillP(const Color(0xFFF4F1EE)));
      canvas.drawCircle(Offset(ey.dx + flip * 0.008 * hs * s, ey.dy), 0.018 * hs * s, _fillP(const Color(0xFF1B120C)));
      final brow = Path();
      _mv(brow, pt(0.12, -0.14));
      brow.quadraticBezierTo(pt(0.22, -0.16).dx, pt(0.22, -0.16).dy, pt(0.31, -0.13).dx, pt(0.31, -0.13).dy);
      canvas.drawPath(brow, _strokeP(hairCol, 0.022 * hs * s));
      final mouth = Path();
      _mv(mouth, pt(0.31, 0.225));
      _ln(mouth, pt(0.34, 0.235));
      canvas.drawPath(mouth, _strokeP(const Color(0xFF8F5A3C), 0.016 * hs * s));
      canvas.restore();
    }
  }

  // ---- one arm: shoulder, upper arm, forearm, hand
  void arm(_Side sd, double ref) {
    final dk = dimK((dep(sd.shoulder) + dep(sd.elbow) + dep(sd.wrist)) / 3, ref);

    // the biceps swell as the elbow bends
    var flex = 0.0;
    if (!p.lying && !p.lockBar) {
      final u = (sd.shoulder - sd.elbow).unit, v = (sd.wrist - sd.elbow).unit;
      final ang = math.acos(_cl(u.dot(v), -1, 1));
      flex = _cl((math.pi - ang) * 180 / math.pi / 150, 0, 1);
    }
    _Prof prof(_Prof base, double amp) => [
          for (var i = 0; i <= 10; i++)
            (i / 10, _interp(base, i / 10) + amp * math.exp(-math.pow((i / 10 - 0.5) / 0.22, 2)))
        ];
    // muscles show even with a straight arm, and get bigger when the arm flexes
    final uF = prof(_armF, 0.04 + 0.09 * flex);
    final uB = prof(_armB, 0.03 + 0.05 * flex);
    final uL = prof(_armL, 0.03 + 0.04 * flex);

    // shoulder (deltoid), upper arm, forearm
    final sc = mv(sd.shoulder);
    canvas.drawCircle(
        sc,
        0.25 * s,
        _shaderP(ui.Gradient.radial(sc + Offset(0.07 * s, -0.07 * s), 0.30 * s,
            _dim([_skin[1], _skin[2], _skin[3]], dk), const [0.0, 0.55, 1.0])));
    final upper = tube(sd.shoulder, sd.elbow, uF, uB, uL, _skin, capA: false, dark: dk);
    tube(sd.elbow, sd.wrist, _foreF, _foreB, _foreL, _skin, dark: dk);
    final vf = visF(upper.f), vb = visB(upper.f);

    // biceps peak and triceps line
    crv([
      surf(sd.shoulder, sd.elbow, 0.15, 1, 0.15),
      surf(sd.shoulder, sd.elbow, 0.45, 1, 0.15 + 0.07 * flex),
      surf(sd.shoulder, sd.elbow, 0.8, 1, 0.11),
    ], _skin[1], 0.035, 0.55 + 0.3 * flex, vf);
    crv([
      surf(sd.shoulder, sd.elbow, 0.3, -1, 0.1),
      surf(sd.shoulder, sd.elbow, 0.6, -1, 0.11),
      surf(sd.shoulder, sd.elbow, 0.85, -1, 0.05),
    ], _skin[4], 0.016, 0.4, vb);

    // deltoid / triceps horseshoe and forearm line
    crv([
      surf(sd.shoulder, sd.elbow, 0.05, 1, 0.2),
      surf(sd.shoulder, sd.elbow, 0.25, 1, 0.24),
    ], _skin[4], 0.02, 0.5, vf);
    crv([
      surf(sd.elbow, sd.wrist, 0.1, 1, 0.12),
      surf(sd.elbow, sd.wrist, 0.35, 1, 0.14),
      surf(sd.elbow, sd.wrist, 0.65, 1, 0.07),
    ], _skin[1], 0.03, 0.45, vf);

    final angA = projAng(sd.shoulder, sd.elbow);
    if (focus.contains(FigMuscle.biceps)) {
      glowAt(surf(sd.shoulder, sd.elbow, 0.45, 1, 0.08 + 0.05 * flex), 0.16, 0.28, angA, upper.path, vf);
    }
    if (focus.contains(FigMuscle.triceps)) {
      glowAt(surf(sd.shoulder, sd.elbow, 0.5, -1, 0.08), 0.18, 0.32, angA, upper.path, vb);
    }

    // elbow and hand
    blob(pr(sd.elbow), 0.11, 0.11, 0, _skin[3], 0.35);
    final hc = sd.wrist + (sd.wrist - sd.elbow).unit * 0.07;
    final hp = mv(hc);
    canvas.drawCircle(
        hp,
        0.14 * s,
        _shaderP(ui.Gradient.radial(hp + Offset(0.04 * s, -0.04 * s), 0.14 * s,
            _dim([_skin[1], _skin[2], _skin[3]], dk), const [0.0, 0.5, 1.0])));
  }

  // ---- barbell / dumbbells
  void equipment(_Body bd, List<_Item> items) {
    if (equip == FigEquip.barbell) {
      final w = (bd.sides[0].wrist + bd.sides[1].wrist) / 2; // on the centre line
      final r = p.lying ? 0.40 : 0.50;
      items.add(_Item(dep(w) - 0.02, () {
        canvas.drawLine(mv(w + const _V3(0, 0, 1.3)), mv(w - const _V3(0, 0, 1.3)), _strokeP(const Color(0xFFB9C4C1), 0.05 * s));
      }));
      for (final sd in const [1.0, -1.0]) {
        final c = w + _V3(0, 0, sd * 1.05);
        final near = dep(c) > dep(w) + 0.2;
        items.add(_Item(dep(c), () => plate(c, r, 0.13, near ? 0.55 : 1)));
      }
    } else if (equip == FigEquip.dumbbell) {
      for (final sd in bd.sides) {
        final hc = sd.wrist + (sd.wrist - sd.elbow).unit * 0.07;
        items.add(_Item(dep(hc) + 0.05, () {
          canvas.drawLine(mv(hc + const _V3(0, 0, 0.2)), mv(hc - const _V3(0, 0, 0.2)), _strokeP(const Color(0xFF9AA5A2), 0.07 * s));
          plate(hc + const _V3(0, 0, 0.17), 0.2, 0.08, 1);
          plate(hc - const _V3(0, 0, 0.17), 0.2, 0.08, 1);
        }));
      }
    }
  }

  /// a weight plate: a disc whose axis points sideways
  void plate(_V3 c, double r, double th, double alpha) {
    final z1 = c + _V3(0, 0, th / 2), z2 = c - _V3(0, 0, th / 2);
    final nearFirst = dep(z1) >= dep(z2);
    final pn = mv(nearFirst ? z1 : z2), pf = mv(nearFirst ? z2 : z1);
    final rx = r * cy.abs() * s, ry = r * s;
    canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: alpha));
    canvas.drawOval(Rect.fromCenter(center: pf, width: 2 * rx, height: 2 * ry), _fillP(const Color(0xFF111715)));
    canvas.drawRect(Rect.fromLTRB(math.min(pf.dx, pn.dx), pn.dy - ry, math.max(pf.dx, pn.dx), pn.dy + ry),
        _fillP(const Color(0xFF1B2321)));
    canvas.drawOval(
        Rect.fromCenter(center: pn, width: 2 * rx, height: 2 * ry),
        _shaderP(ui.Gradient.radial(Offset(pn.dx - 0.15 * rx, pn.dy - 0.2 * ry), math.max(rx, ry) * 1.2,
            const [Color(0xFF4A5754), Color(0xFF222B29), Color(0xFF111715)], const [0.0, 0.6, 1.0])));
    canvas.drawOval(Rect.fromCenter(center: pn, width: 2 * rx * 0.84, height: 2 * ry * 0.84),
        _strokeP(const Color(0xFFB9C4C1), r * s * 0.05, 0.8));
    canvas.drawOval(Rect.fromCenter(center: pn, width: 2 * rx * 0.5, height: 2 * ry * 0.5),
        _strokeP(const Color(0xFF0B100F), r * s * 0.03, 0.9));
    canvas.drawOval(Rect.fromCenter(center: pn, width: 2 * rx * 0.22, height: 2 * ry * 0.22), _fillP(const Color(0xFFB8C2BF)));
    canvas.restore();
  }
}

class _FigPainter extends CustomPainter {
  _FigPainter(this.p, this.equip, this.bad, this.focus, this.glow, this.yaw);
  final FigPose p;
  final FigEquip equip;
  final bool bad;
  final Set<FigMuscle> focus;
  final double glow;
  final double yaw;

  @override
  void paint(Canvas canvas, Size size) {
    _FigDraw(canvas, size, p, equip, bad, focus, glow, yaw).draw();
  }

  @override
  bool shouldRepaint(_FigPainter old) => true;
}

// ------------------------------------------------------------------------------------------
// widgets
// ------------------------------------------------------------------------------------------

/// the trainer, animated when the step has two different poses.
/// [yaw] is the camera angle in degrees (0 = side, 270 = front, 90 = back); give it a
/// ValueNotifier to turn the trainer, leave it null for the plain side view.
class ExerciseFigure extends StatefulWidget {
  const ExerciseFigure(this.step, {super.key, this.height = 130, this.focus = const [], this.yaw});
  final FigStep step;
  final double height;
  final ValueListenable<double>? yaw;

  /// muscles that glow (ignored for a mistake picture)
  final List<FigMuscle> focus;

  @override
  State<ExerciseFigure> createState() => _ExerciseFigureState();
}

class _ExerciseFigureState extends State<ExerciseFigure> with TickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  bool get _glows => widget.focus.isNotEmpty && !widget.step.bad;

  @override
  void initState() {
    super.initState();
    if (widget.step.moves) _c.repeat(reverse: true);
    if (_glows) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.step;
    final focus = widget.focus.toSet();
    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const RadialGradient(center: Alignment(0, 0.1), radius: 0.95, colors: [Sp.cardHigh, Sp.card]),
        borderRadius: BorderRadius.circular(Sp.rButton),
        border: Border.all(color: st.bad ? Sp.fault : Sp.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Sp.rButton),
        child: Stack(children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_c, _pulse, if (widget.yaw != null) widget.yaw!]),
              builder: (_, _) => CustomPaint(
                painter: _FigPainter(
                  FigPose.lerp(st.from, st.to, Curves.easeInOut.transform(_c.value)),
                  st.equip,
                  st.bad,
                  _glows ? focus : const <FigMuscle>{},
                  _glows ? 0.55 + 0.45 * Curves.easeInOut.transform(_pulse.value) : 0,
                  widget.yaw?.value ?? 0,
                ),
              ),
            ),
          ),
          if (st.bad)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(color: Sp.fault, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 18, color: Colors.white),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The coach: one big trainer who shows the whole movement first and then each step, with the
/// explanation of the step written right under him. Back / Next walk through the steps.
/// The trainer spins 360 degrees by default; drag on him to turn him by hand, or tap
/// Front / Side / Back / 360.
class TrainerGuide extends StatefulWidget {
  const TrainerGuide({
    super.key,
    required this.demo,
    required this.steps,
    this.focus = const [],
    this.stageHeight = 250,
  });

  /// the looping movement shown first
  final FigStep demo;

  /// every step: the picture and what the coach says
  final List<(FigStep, String)> steps;

  /// the muscles this exercise works (they glow on the trainer)
  final List<FigMuscle> focus;
  final double stageHeight;

  @override
  State<TrainerGuide> createState() => _TrainerGuideState();
}

class _TrainerGuideState extends State<TrainerGuide> with SingleTickerProviderStateMixin {
  int _i = 0; // 0 = the whole movement, 1.. = the steps

  // camera
  final ValueNotifier<double> _yaw = ValueNotifier<double>(0);
  late final Ticker _tick = createTicker(_onTick);
  Duration _last = Duration.zero;
  bool _auto = true;
  FigEquip? _equip; // null = what the step says

  @override
  void initState() {
    super.initState();
    _tick.start();
  }

  @override
  void dispose() {
    _tick.dispose();
    _yaw.dispose();
    super.dispose();
  }

  void _onTick(Duration t) {
    final dt = (t - _last).inMicroseconds / 1e6;
    _last = t;
    _yaw.value = (_yaw.value + dt * 28) % 360; // one turn in about 13 seconds
  }

  void _setAuto(bool on) {
    setState(() => _auto = on);
    if (on) {
      _last = Duration.zero;
      if (!_tick.isActive) _tick.start();
    } else {
      if (_tick.isActive) _tick.stop();
    }
  }

  void _view(double deg) {
    _setAuto(false);
    _yaw.value = deg;
  }

  bool _isView(double deg) {
    if (_auto) return false;
    final d = (_yaw.value - deg) % 360; // 0..360
    return d < 1 || d > 359;
  }

  int get _count => widget.steps.length + 1;
  FigStep get _fig {
    final st = _i == 0 ? widget.demo : widget.steps[_i - 1].$1;
    final e = _equip;
    return (e == null || st.equip == FigEquip.none) ? st : st.withEquip(e);
  }

  /// the bench press can be shown with a bar or with dumbbells
  bool get _benchPress => widget.demo.from.lying;
  FigEquip get _currentEquip => _equip ?? widget.demo.equip;
  String get _text =>
      _i == 0 ? 'Watch the whole movement once, then tap Next and I will take you through it step by step.' : widget.steps[_i - 1].$2;

  void _go(int i) => setState(() => _i = i.clamp(0, _count - 1).toInt());

  Widget _viewChip(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? Sp.mint : Sp.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? Sp.mint : Sp.line),
          ),
          child: Text(label, style: Sp.labelMd.copyWith(color: on ? Colors.black : Sp.white)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bad = _fig.bad;
    final accent = bad ? Sp.fault : Sp.mint;
    final last = _i == _count - 1;
    final title = _i == 0 ? 'The movement' : (bad ? 'Avoid this' : 'Step $_i of ${_count - 1}');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      // the coach (drag to turn him)
      GestureDetector(
        onHorizontalDragUpdate: (d) {
          if (_auto) _setAuto(false);
          _yaw.value = (_yaw.value + d.delta.dx * 0.8) % 360;
        },
        child: Stack(children: [
          ExerciseFigure(_fig, key: ValueKey(_i), height: widget.stageHeight, focus: widget.focus, yaw: _yaw),
          Positioned(
            top: 10,
            left: 10,
            child: SpotChip(_i == 0 ? 'Coach' : '$_i / ${_count - 1}', dot: accent),
          ),
          if (widget.focus.isNotEmpty && !bad)
            Positioned(
              left: 10,
              bottom: 10,
              right: 10,
              child: Row(children: [
                Flexible(
                  child: SpotChip('Working: ${widget.focus.map((m) => m.label).join(', ')}', dot: Sp.mint),
                ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 10),

      if (_benchPress) ...[
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _viewChip('Barbell', _currentEquip == FigEquip.barbell, () => setState(() => _equip = FigEquip.barbell)),
          const SizedBox(width: 8),
          _viewChip('Dumbbells', _currentEquip == FigEquip.dumbbell, () => setState(() => _equip = FigEquip.dumbbell)),
        ]),
        const SizedBox(height: 8),
      ],

      // camera
      AnimatedBuilder(
        animation: _yaw,
        builder: (_, _) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _viewChip('Front', _isView(270), () => _view(270)),
          const SizedBox(width: 8),
          _viewChip('Side', _isView(0), () => _view(0)),
          const SizedBox(width: 8),
          _viewChip('Back', _isView(90), () => _view(90)),
          const SizedBox(width: 8),
          _viewChip('360°', _auto, () => _setAuto(!_auto)),
        ]),
      ),
      const SizedBox(height: 12),

      // what the coach says, under him
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Sp.card,
          borderRadius: BorderRadius.circular(Sp.rButton),
          border: Border.all(color: bad ? Sp.fault : Sp.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: Sp.labelMd.copyWith(color: accent)),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, if (current != null) current],
            ),
            child: SizedBox(
              key: ValueKey(_i),
              width: double.infinity,
              child: Text(_text, style: Sp.bodyLg.copyWith(color: Sp.white)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),

      // progress dots
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var k = 0; k < _count; k++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _go(k),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: k == _i ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: k == _i ? accent : Sp.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 4),

      Row(children: [
        Expanded(
          child: SpotButton('Back',
              kind: SpotKind.secondary,
              icon: Icons.arrow_back,
              height: 48,
              onPressed: _i == 0 ? null : () => _go(_i - 1)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SpotButton(last ? 'Replay' : 'Next',
              icon: last ? Icons.replay : Icons.arrow_forward,
              height: 48,
              onPressed: () => _go(last ? 0 : _i + 1)),
        ),
      ]),
    ]);
  }
}