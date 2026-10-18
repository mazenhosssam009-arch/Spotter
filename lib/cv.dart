import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// colors used by the python code (cv2 uses BGR, these are the same colors in RGB)
const blue = Color(0xFF0000FF); // (255,0,0) in cv2
const green = Color(0xFF00FF00); // (0,255,0)
const red = Color(0xFFFF0000); // (0,0,255)
const magenta = Color(0xFFFF00FF); // (255,0,255)
const black = Color(0xFF000000); // (0,0,0)
const white = Color(0xFFE0E0E0); // mediapipe connection color
const filled = -1.0; // cv2.FILLED

typedef _Op = void Function(Canvas canvas, Size size, double sx, double sy);

/// One camera frame: the image that goes to the detector ("imgRGB") plus the
/// things drawn on it, in image pixel coordinates, like cv2 drawing on img.
class Frame {
  Frame(this.input, this.width, this.height, {this.mirror = false, this.swapLeftRight = false, this.detectScale = 1})
      : _ops = [];
  Frame._(this.input, this.width, this.height, this.mirror, this._ops, this.detectScale,
      this.swapLeftRight);

  final InputImage input;
  final double width, height;
  // the detector gets a smaller copy of the picture; multiply its results by this
  // to get pixels of the real (width x height) picture
  final double detectScale;
  // the front camera preview is mirrored, so drawings on the body are mirrored too
  final bool mirror;
  // iOS front camera: the detector sees a mirrored person, so left/right labels are swapped
  final bool swapLeftRight;
  final List<_Op> _ops;

  /// same frame but not mirrored: for the bar, counter and fps text
  Frame get hud => Frame._(input, width, height, false, _ops, detectScale, swapLeftRight);

  Offset _p(num x, num y) => Offset(mirror ? width - x : x.toDouble(), y.toDouble());

  Paint _paint(Color color, double thickness, double sx) => Paint()
    ..color = color
    ..style = thickness < 0 ? PaintingStyle.fill : PaintingStyle.stroke
    ..strokeWidth = thickness < 0 ? 0 : thickness * sx;

  void line(int x1, int y1, int x2, int y2, Color color, double thickness) {
    final a = _p(x1, y1), b = _p(x2, y2);
    _ops.add((c, s, sx, sy) =>
        c.drawLine(a.scale(sx, sy), b.scale(sx, sy), _paint(color, thickness, sx)));
  }

  void circle(int x, int y, double radius, Color color, double thickness) {
    final o = _p(x, y);
    _ops.add((c, s, sx, sy) =>
        c.drawCircle(o.scale(sx, sy), radius * sx, _paint(color, thickness, sx)));
  }

  void rectangle(num x1, num y1, num x2, num y2, Color color, double thickness) {
    final a = _p(x1, y1), b = _p(x2, y2);
    _ops.add((c, s, sx, sy) => c.drawRect(
        Rect.fromPoints(a.scale(sx, sy), b.scale(sx, sy)), _paint(color, thickness, sx)));
  }

  /// like cv2.putText: (x,y) is the bottom left corner of the text
  void putText(String text, num x, num y, double fontScale, Color color, double thickness) {
    final o = _p(x, y);
    _ops.add((c, s, sx, sy) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: 30 * fontScale * sy,
            fontWeight: thickness >= 3 ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // keep the text inside the screen
      final dx = (o.dx * sx).clamp(0.0, (s.width - tp.width).clamp(0.0, s.width));
      final dy = (o.dy * sy - tp.height * 0.85).clamp(0.0, (s.height - tp.height).clamp(0.0, s.height));
      tp.paint(c, Offset(dx, dy));
    });
  }
}

/// draws a Frame on top of the camera preview ("cv2.imshow").
/// It listens to [frame], so only this layer repaints when a new frame arrives
/// (the camera preview under it is not rebuilt).
class FramePainter extends CustomPainter {
  FramePainter(this.frame) : super(repaint: frame);
  final ValueListenable<Frame?> frame;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame.value;
    if (f == null) return;
    final sx = size.width / f.width, sy = size.height / f.height;
    for (final op in f._ops) {
      op(canvas, size, sx, sy);
    }
  }

  @override
  bool shouldRepaint(FramePainter old) => old.frame != frame;
}

/// np.interp: maps x from (x0,x1) to (y0,y1), clamped to the ends
double interp(double x, double x0, double x1, double y0, double y1) {
  if (x <= x0) return y0;
  if (x >= x1) return y1;
  return y0 + (x - x0) * (y1 - y0) / (x1 - x0);
}

/// time.time()
double now() => DateTime.now().microsecondsSinceEpoch / 1e6;