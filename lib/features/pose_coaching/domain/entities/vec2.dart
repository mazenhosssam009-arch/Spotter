import 'dart:math' as math;

/// a 2D point / vector in picture pixels (like Flutter's Offset, without Flutter)
class Vec2 {
  const Vec2(this.dx, this.dy);
  final double dx;
  final double dy;

  Vec2 operator +(Vec2 o) => Vec2(dx + o.dx, dy + o.dy);
  Vec2 operator -(Vec2 o) => Vec2(dx - o.dx, dy - o.dy);
  Vec2 operator /(double v) => Vec2(dx / v, dy / v);

  double get distance => math.sqrt(dx * dx + dy * dy);
}
