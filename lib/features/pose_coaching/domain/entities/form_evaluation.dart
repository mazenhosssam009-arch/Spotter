/// result of the form checks for one frame
class FormEvaluation {
  final scores = <double>[]; // one 0..1 score per alignment check
  final warns = <String>[]; // messages for checks that are out of tolerance
  final blocking = <String>[]; // clear faults: these reject the rep
  bool assessable = false; // false = not enough landmarks to judge form
  String? note; // small grey hint ("flare unchecked")

  /// [over] > 0 means outside tolerance; the score reaches 0 at [over] == [soft].
  /// A fault only blocks the rep when it is clearly outside tolerance (score < 0.5).
  void limit(double over, double soft, String msg, {bool block = false, double? blockAt}) {
    if (!over.isFinite) return;
    final s = over <= 0 ? 1.0 : (1 - over / soft).clamp(0.0, 1.0).toDouble();
    scores.add(s);
    if (over > 0) {
      warns.add(msg);
      // blockAt: reject the rep only when [over] reaches this (warn earlier, reject later)
      if (block && (blockAt != null ? over >= blockAt : s < 0.5)) blocking.add(msg);
    }
  }
}
