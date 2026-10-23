import 'package:flutter/material.dart';

// colors used by the python code (cv2 uses BGR, these are the same colors in RGB)
const blue = Color(0xFF0000FF); // (255,0,0) in cv2
const green = Color(0xFF00FF00); // (0,255,0)
const red = Color(0xFFFF0000); // (0,0,255)
const magenta = Color(0xFFFF00FF); // (255,0,255)
const black = Color(0xFF000000); // (0,0,0)
const white = Color(0xFFE0E0E0); // mediapipe connection color
const filled = -1.0; // cv2.FILLED

typedef _Op = void Function(Canvas canvas, Size size, double sx, double sy);

/// What is drawn on one camera frame, in image pixel coordinates, like cv2
/// drawing on img. [OverlayPainter] puts it on top of the camera preview.
class OverlayFrame {
  OverlayFrame(this.width, this.height, {this.mirror = false}) : _ops = [];
  OverlayFrame._(this.width, this.height, this.mirror, this._ops);

  final double width, height;
  // the front camera preview is mirrored, so drawings on the body are mirrored too
  final bool mirror;
  final List<_Op> _ops;

  /// same frame but not mirrored: for the bar, counter and fps text
  OverlayFrame get hud => OverlayFrame._(width, height, false, _ops);

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

/// draws an OverlayFrame on top of the camera preview ("cv2.imshow")
class OverlayPainter extends CustomPainter {
  OverlayPainter(this.frame);
  final OverlayFrame? frame;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    if (f == null) return;
    final sx = size.width / f.width, sy = size.height / f.height;
    for (final op in f._ops) {
      op(canvas, size, sx, sy);
    }
  }

  @override
  bool shouldRepaint(OverlayPainter old) => old.frame != frame;
}
