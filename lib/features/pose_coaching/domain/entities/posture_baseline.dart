/// The user's own start posture, one number per measure (lean, torso length, standing
/// hip angle...). Body type and camera angle differ, so the form checks compare with
/// this instead of one fixed number. It slowly follows while the user is idle and is
/// frozen during a rep.
class PostureBaseline {
  final _values = <String, double>{};

  double? operator [](String key) => _values[key];
  void operator []=(String key, double value) => _values[key] = value;

  void remove(String key) => _values.remove(key);
  void clear() => _values.clear();

  /// the start posture of [key]: learned from the first value, follows slowly while [idle]
  double follow(String key, double v, bool idle) {
    final b = _values[key];
    if (b == null) {
      _values[key] = v;
      return v;
    }
    if (idle) return _values[key] = 0.95 * b + 0.05 * v;
    return b;
  }

  /// like [follow], but follows the start posture faster while idle (curl swing checks):
  /// a stale start posture (arm just swapped in alternate mode) is forgotten within a second
  double quickFollow(String key, double v, bool idle) {
    final b = _values[key];
    if (b == null) {
      _values[key] = v;
      return v;
    }
    if (idle) return _values[key] = 0.85 * b + 0.15 * v;
    return b;
  }

  /// like [follow], but only follows while idle AND near the upright value, so a slow
  /// start of the lift cannot drag the "standing" reference down with it
  double standing(String key, double v, bool idle) {
    final b = _values[key];
    if (b == null) {
      _values[key] = v;
      return v;
    }
    if (!idle) return b;
    if (v > b) return _values[key] = 0.8 * b + 0.2 * v;
    if (v > 0.9 * b) return _values[key] = 0.95 * b + 0.05 * v;
    return _values[key] = 0.9995 * b; // far below: slow drift, so one early spike can't stick
  }
}
