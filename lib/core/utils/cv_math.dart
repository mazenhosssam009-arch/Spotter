/// np.interp: maps x from (x0,x1) to (y0,y1), clamped to the ends
double interp(double x, double x0, double x1, double y0, double y1) {
  if (x <= x0) return y0;
  if (x >= x1) return y1;
  return y0 + (x - x0) * (y1 - y0) / (x1 - x0);
}

/// time.time()
double now() => DateTime.now().microsecondsSinceEpoch / 1e6;

/// seconds as m:ss
String mmss(double s) {
  final v = s.isFinite ? s.round() : 0;
  return '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
}
